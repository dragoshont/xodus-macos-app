// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import Foundation

struct GameInstallConsent: Identifiable, Sendable {
    let id = UUID()
    let game: PCGame
    let destination: URL
    let freeBytes: Int64
    let installedID: UUID?
    var compatibility: GameCompatibilityResult?
    var checkError: String?
}

@MainActor
final class GameOperationsController: ObservableObject {
    @Published private(set) var serviceStatus: GameServiceStatus?
    @Published private(set) var serviceBusy = false
    @Published private(set) var serviceSigningIn = false
    @Published private(set) var serviceError: String?
    @Published private(set) var serviceLog: URL?
    @Published var installConsent: GameInstallConsent?
    @Published var uninstallConsent: InstalledGame?
    @Published private(set) var preparingConsent = false
    @Published private(set) var checkingCompatibility = false
    @Published private(set) var compatibility: [String: GameCompatibilityResult] = [:]
    @Published private(set) var compatibilityErrors: [String: String] = [:]
    @Published private(set) var operation: GameOperationRecord?
    @Published private(set) var progress: GameScriptProgress?
    @Published private(set) var cancelling = false
    @Published private(set) var checkingRecovery = false
    @Published private(set) var recoveryRequired = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var log: URL?
    @Published private(set) var failureCode: Int?
    private let installed: InstalledGamesController
    private let paths: GameScriptPaths
    private let mutationRunner: GameScriptRunner
    private let serviceRunner: GameScriptRunner
    private let journal: GameOperationJournal
    private var mutationTask: Task<Void, Never>?
    private var serviceTask: Task<Void, Never>?
    private var compatibilityTask: Task<Void, Never>?
    private var compatibilityRunID: String?
    private var restored = false
    private var terminating = false
    private var installedObservation: AnyCancellable?

    var isBusy: Bool { operation != nil || checkingCompatibility }
    var canSignIn: Bool {
        !serviceBusy && !isBusy && !recoveryRequired && !installed.mutationActive
            && installed.runningGameID == nil && !terminating
    }
    var canStartMutation: Bool {
        !isBusy && !recoveryRequired && !installed.mutationActive && !serviceSigningIn && !preparingConsent && installed.loaded
            && !installed.editing && !installed.choosing && !terminating
    }
    var canQuit: Bool { mutationTask == nil && compatibilityTask == nil && !serviceSigningIn }
    var canConfirmInstall: Bool {
        canStartMutation && installConsent?.compatibility?.supported == true
    }
    var canCancel: Bool {
        operation?.kind != .uninstall && isBusy && !recoveryRequired && !cancelling
    }
    var serviceLabel: String {
        serviceStatus?.signedIn == true ? "Signed in for games"
            : serviceStatus == nil ? "Game sign-in hasn't been checked" : "Sign in for games"
    }

    init(installed: InstalledGamesController, paths: GameScriptPaths = .production) {
        self.installed = installed
        self.paths = paths
        mutationRunner = GameScriptRunner(paths: paths)
        serviceRunner = GameScriptRunner(paths: paths)
        journal = GameOperationJournal(file: paths.journal)
        installedObservation = installed.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func restore() async {
        guard !restored, !isBusy, !terminating else { return }
        restored = true
        do {
            guard let record = try await journal.load() else { return }
            try installed.reserveMutation(gameID: record.installedID)
            operation = record
            recoveryRequired = true
            error = "The last game operation needs checking. No operation will be repeated automatically."
            log = await Task.detached { GameScriptFiles.log(runID: record.id, paths: self.paths) }.value
        } catch {
            recoveryRequired = true
            self.error = GameScriptError.storage.localizedDescription
            // Keep mutations fenced when a saved operation cannot be understood.
            if !installed.mutationActive { try? installed.reserveMutation(gameID: nil) }
        }
    }

    func refreshService() {
        guard !serviceBusy, !terminating else { return }
        serviceBusy = true
        serviceError = nil
        let runID = InstalledGamesController.runID()
        serviceTask = Task {
            defer { serviceBusy = false; serviceTask = nil }
            do {
                let outcome = try await serviceRunner.run(command: .serviceStatus, runID: runID)
                guard !terminating else { return }
                guard outcome.code == 0, let data = outcome.result else { throw GameScriptError.failed(outcome.code) }
                serviceStatus = try GameServiceStatus.parse(data)
                serviceLog = nil
            } catch {
                guard !terminating else { return }
                serviceStatus = nil
                serviceError = Self.message(error)
                serviceLog = await scriptLog(runID)
            }
        }
    }

    func signInForGames() {
        guard canSignIn else { return }
        serviceBusy = true
        serviceSigningIn = true
        installed.serviceSignInActive = true
        serviceError = nil
        serviceLog = nil
        let runID = InstalledGamesController.runID()
        serviceTask = Task {
            defer {
                serviceBusy = false
                serviceSigningIn = false
                installed.serviceSignInActive = false
                serviceTask = nil
            }
            do {
                let signedIn = try await serviceRunner.run(command: .serviceSignIn, runID: runID)
                guard signedIn.code == 0 else { throw GameScriptError.failed(signedIn.code) }
                let status = try await serviceRunner.run(command: .serviceStatus, runID: InstalledGamesController.runID())
                guard status.code == 0, let data = status.result else { throw GameScriptError.invalidReceipt }
                let value = try GameServiceStatus.parse(data)
                guard value.signedIn else { throw GameScriptError.failed(11) }
                serviceStatus = value
            } catch {
                serviceStatus = nil
                serviceError = Self.message(error)
                serviceLog = await scriptLog(runID)
            }
        }
    }

    func prepareInstall(_ game: PCGame, repairing: InstalledGame? = nil) async {
        guard canStartMutation, PCGamesClient.validProductID(game.id) else { return }
        if let repairing {
            guard repairing.storeId == game.id, installed.games.contains(repairing),
                  installed.runningGameID != repairing.id else { return }
        }
        preparingConsent = true
        defer { preparingConsent = false }
        do {
            let destination = try repairing.map { URL(fileURLWithPath: $0.folder, isDirectory: true) }
                ?? paths.destination(title: game.title, productID: game.id)
            let free = try await Task.detached { try GameScriptFiles.availableSpace(for: destination) }.value
            guard !terminating, !isBusy else { return }
            if repairing == nil, installed.games.contains(where: { $0.folder == destination.path }) {
                throw GameScriptError.invalidDestination
            }
            installConsent = GameInstallConsent(game: game, destination: destination,
                                                freeBytes: free, installedID: repairing?.id)
            error = nil
            preparingConsent = false
            try installed.reserveMutation(gameID: repairing?.id)
            checkingCompatibility = true
            let runID = InstalledGamesController.runID()
            compatibilityRunID = runID
            log = nil
            failureCode = nil
            compatibilityTask = Task {
                defer {
                    checkingCompatibility = false
                    compatibilityRunID = nil
                    compatibilityTask = nil
                    installed.releaseMutation()
                }
                do {
                    let outcome = try await mutationRunner.run(command: .check, runID: runID, arguments: [game.id])
                    guard compatibilityRunID == runID, installConsent?.game.id == game.id else { return }
                    log = outcome.log
                    guard outcome.code == 0, let data = outcome.result else {
                        failureCode = outcome.code
                        throw GameScriptError.failed(outcome.code)
                    }
                    let result = try GameCompatibilityResult.parse(data, productID: game.id)
                    compatibility[game.id] = result
                    compatibilityErrors[game.id] = nil
                    installConsent?.compatibility = result
                } catch {
                    guard installConsent?.game.id == game.id else { return }
                    installConsent?.checkError = Self.message(error)
                    log = await scriptLog(runID)
                }
            }
            await compatibilityTask?.value
        } catch { self.error = Self.message(error) }
    }

    func confirmInstall(_ consent: GameInstallConsent) {
        guard installConsent?.id == consent.id, canConfirmInstall, !recoveryRequired,
              consent.compatibility?.supported == true else { return }
        installConsent = nil
        let record = GameOperationRecord(id: InstalledGamesController.runID(),
            kind: consent.installedID == nil ? .install : .repair, productID: consent.game.id,
            title: consent.game.title, destination: consent.destination.path, installedID: consent.installedID)
        if let id = consent.installedID,
           !installed.games.contains(where: { $0.id == id && $0.storeId == record.productID && $0.folder == record.destination }) {
            error = "This game's installed entry changed. Choose it again."
            return
        }
        if consent.installedID == nil, installed.games.contains(where: { $0.folder == record.destination }) {
            error = GameScriptError.invalidDestination.localizedDescription
            return
        }
        begin(record)
    }

    func cancelInstallConsent() async {
        installConsent = nil
        guard let runID = compatibilityRunID else { return }
        await mutationRunner.cancel(runID: runID)
        await compatibilityTask?.value
    }

    func loadCompatibility(productID: String) async {
        guard PCGamesClient.validProductID(productID) else { return }
        let paths = paths
        do {
            let result = try await Task.detached {
                guard let data = try GameScriptFiles.read(paths.compatibilityFile(productID: productID),
                                                          missingAllowed: true) else { return Optional<GameCompatibilityResult>.none }
                return try GameCompatibilityResult.parse(data, productID: productID)
            }.value
            if let result {
                if let previous = compatibility[productID]?.checkedDate, let date = result.checkedDate, date < previous { return }
            }
            compatibility[productID] = result
            compatibilityErrors[productID] = nil
        } catch {
            compatibility[productID] = nil
            compatibilityErrors[productID] = "Mac support details couldn't be read. Choose Install to check again."
        }
    }

    func prepareUninstall(_ game: InstalledGame) {
        guard canStartMutation, !recoveryRequired, installed.games.contains(game),
              installed.runningGameID != game.id else { return }
        uninstallConsent = game
    }

    func confirmUninstall(_ game: InstalledGame) {
        guard uninstallConsent?.id == game.id, canStartMutation, !recoveryRequired,
              installed.games.contains(game), installed.runningGameID != game.id else { return }
        uninstallConsent = nil
        begin(GameOperationRecord(id: InstalledGamesController.runID(), kind: .uninstall,
            productID: game.storeId, title: game.title, destination: game.folder, installedID: game.id))
    }

    private func begin(_ record: GameOperationRecord) {
        do { try installed.reserveMutation(gameID: record.installedID) }
        catch { self.error = Self.message(error); return }
        operation = record
        progress = nil
        notice = nil
        error = nil
        log = nil
        failureCode = nil
        mutationTask = Task {
            do {
                try await journal.save(record)
                if cancelling {
                    try await complete(record, outcome: GameScriptOutcome(code: 14, result: nil, log: nil))
                    mutationTask = nil
                    cancelling = false
                    return
                }
                let args = [record.productID, record.destination]
                let outcome = try await mutationRunner.run(
                    command: record.kind == .uninstall ? .uninstall : .install,
                    runID: record.id, arguments: args, progress: { [weak self] value in
                        await self?.publishProgress(value, runID: record.id)
                    })
                log = outcome.log
                try await complete(record, outcome: outcome)
            } catch {
                self.error = Self.message(error)
                log = await scriptLog(record.id)
                if let scriptError = error as? GameScriptError,
                   [.missingStatus, .statusMismatch, .unavailable, .invalidDestination, .invalidProgress].contains(scriptError) {
                    do {
                        try await journal.clear()
                        operation = nil
                        installed.releaseMutation()
                    } catch { self.error = GameScriptError.storage.localizedDescription; recoveryRequired = true }
                } else { recoveryRequired = true }
            }
            mutationTask = nil
            cancelling = false
        }
    }

    private func complete(_ record: GameOperationRecord, outcome: GameScriptOutcome) async throws {
        guard operation?.id == record.id else { throw GameScriptError.invalidReceipt }
        if outcome.code == 0 {
            if record.kind == .uninstall {
                guard let id = record.installedID else { throw GameScriptError.invalidReceipt }
                try await installed.removeUninstalled(id)
                notice = "\(record.title) was uninstalled. Your saves are kept."
            } else {
                guard let data = outcome.result else { throw GameScriptError.invalidReceipt }
                let result = try JSONDecoder().decode(GameInstallResult.self, from: data)
                guard result.storeId == record.productID, result.folder == record.destination,
                      result.launcher.hasPrefix("/"), !result.launcher.split(separator: "/").contains(".."),
                      !result.launcher.split(separator: "/").contains(".") else {
                    throw GameScriptError.invalidReceipt
                }
                let folder = URL(fileURLWithPath: result.folder), launcher = URL(fileURLWithPath: result.launcher)
                try await Task.detached {
                    try GameScriptFiles.checkPath(folder)
                    try GameScriptFiles.checkPath(launcher)
                }.value
                try await installed.registerInstallation(folder: folder, launcher: launcher, expectedStoreID: record.productID)
                notice = record.kind == .repair ? "\(record.title) is ready to play." : "\(record.title) was installed."
            }
        } else {
            failureCode = outcome.code
            if outcome.code == 12 { await loadCompatibility(productID: record.productID) }
            let unsupportedReason = compatibility[record.productID].flatMap { $0.supported ? nil : $0.reason }
                ?? (progress?.phase == .failed ? progress?.message : nil)
            error = outcome.code == 20 && record.kind == .uninstall
                ? "Your saves couldn't be preserved. The game wasn't uninstalled."
                : outcome.code == 12 ? unsupportedReason
                    ?? GameScriptError.failed(outcome.code).localizedDescription
                : GameScriptError.failed(outcome.code).localizedDescription
        }
        try await journal.clear()
        operation = nil
        recoveryRequired = false
        installed.releaseMutation()
    }

    private func publishProgress(_ value: GameScriptProgress, runID: String) {
        guard operation?.id == runID else { return }
        progress = value
    }

    func cancelInstall() async {
        guard canCancel, let operation else { return }
        cancelling = true
        await mutationRunner.cancel(runID: operation.id)
    }

    func reconcile() async {
        guard recoveryRequired, let record = operation, !checkingRecovery, mutationTask == nil else { return }
        checkingRecovery = true
        defer { checkingRecovery = false }
        do {
            let outcome = try await Task.detached {
                guard let data = try GameScriptFiles.read(self.paths.receipt(record.id, suffix: "status"),
                                                          maximumBytes: 32) else { throw GameScriptError.invalidReceipt }
                let code = try GameScriptFiles.status(data)
                let result = code == 0 && record.kind != .uninstall
                    ? try GameScriptFiles.read(self.paths.receipt(record.id, suffix: "result.json")) : nil
                return GameScriptOutcome(code: code, result: result, log: GameScriptFiles.log(runID: record.id, paths: self.paths))
            }.value
            log = outcome.log
            try await complete(record, outcome: outcome)
        } catch { self.error = Self.message(error) }
    }

    func showLog() { if let log { NSWorkspace.shared.activateFileViewerSelecting([log]) } }
    func showServiceLog() { if let serviceLog { NSWorkspace.shared.activateFileViewerSelecting([serviceLog]) } }
    func waitForMutation() async {
        await compatibilityTask?.value
        await mutationTask?.value
    }
    func waitForService() async { await serviceTask?.value }
    func beginTermination() { terminating = true }
    func resumeAfterTerminationRefusal() { terminating = false }

    private func scriptLog(_ runID: String) async -> URL? {
        let paths = paths
        return await Task.detached { GameScriptFiles.log(runID: runID, paths: paths) }.value
    }

    private static func message(_ error: Error) -> String {
        if let typed = error as? GameScriptError { return typed.localizedDescription }
        if let typed = error as? InstalledGameError { return typed.localizedDescription }
        return GameScriptError.invalidReceipt.localizedDescription
    }
}
