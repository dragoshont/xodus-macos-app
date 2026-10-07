// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

enum InstalledGamePlayState: Equatable {
    case launching, playing
}

@MainActor
final class InstalledGamesController: ObservableObject {
    @Published private(set) var games: [InstalledGame] = []
    @Published private(set) var loading = false
    @Published private(set) var editing = false
    @Published private(set) var choosing = false
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var runningGameID: UUID?
    @Published private(set) var playState: InstalledGamePlayState?
    @Published private(set) var playErrors: [UUID: String] = [:]
    var applicationTerminating = false
    private let store: InstalledGameStore
    private let launchingDuration: Duration
    private var playingTask: Task<Void, Never>?
    private var runToken: UUID?
    private var process: Process?

    init(store: InstalledGameStore = InstalledGameStore(), launchingDuration: Duration = .seconds(5)) {
        self.store = store
        self.launchingDuration = launchingDuration
    }

    func load() async {
        guard !loading, !editing, !choosing, !loaded, !applicationTerminating else { return }
        loading = true
        defer { loading = false }
        do {
            games = try await store.load()
            loaded = true
            error = nil
        } catch { self.error = InstalledGameError.invalidRegistry.localizedDescription }
    }

    func importGame(folder: URL, launcher: URL) async {
        guard loaded, !editing, !applicationTerminating else { return }
        editing = true
        defer { editing = false }
        do {
            let metadata = try await Task.detached(priority: .userInitiated) {
                let config = try MicrosoftGameConfig.read(folder: folder)
                try InstalledGameFiles.checkLauncher(launcher)
                return config
            }.value
            let game = InstalledGame(id: games.first(where: { $0.folder == folder.path })?.id ?? UUID(),
                title: metadata.title, identityName: metadata.identityName, version: metadata.version,
                storeId: metadata.storeId, folder: folder.path, launcher: launcher.path, importedAt: Date())
            guard runningGameID != game.id else {
                error = "Wait for this game to finish before changing its launch script."
                return
            }
            var updated = games.filter { $0.folder != game.folder }
            updated.append(game)
            try await store.save(updated)
            games = updated
            error = nil
        } catch {
            self.error = (error as? InstalledGameError)?.localizedDescription
                ?? InstalledGameError.storage.localizedDescription
        }
    }

    func chooseGame() async {
        guard loaded, !editing, !choosing, !applicationTerminating else { return }
        choosing = true
        defer { choosing = false }
        let folderPanel = NSOpenPanel()
        folderPanel.title = "Import installed Xbox game"
        folderPanel.prompt = "Choose game folder"
        folderPanel.canChooseDirectories = true
        folderPanel.canChooseFiles = false
        folderPanel.allowsMultipleSelection = false
        guard await folderPanel.begin() == .OK, let folder = folderPanel.url else { return }
        do {
            _ = try await Task.detached(priority: .userInitiated) { try MicrosoftGameConfig.read(folder: folder) }.value
        } catch {
            self.error = InstalledGameError.invalidConfig.localizedDescription
            return
        }
        let scriptPanel = NSOpenPanel()
        scriptPanel.title = "Choose the launch script for this game"
        scriptPanel.message = "Use the Xodus launch script you already use for this game."
        scriptPanel.prompt = "Choose launch script"
        scriptPanel.canChooseDirectories = false
        scriptPanel.canChooseFiles = true
        scriptPanel.allowsMultipleSelection = false
        guard await scriptPanel.begin() == .OK, let launcher = scriptPanel.url else { return }
        await importGame(folder: folder, launcher: launcher)
    }

    func remove(_ game: InstalledGame) async {
        guard loaded, !editing, !choosing, !applicationTerminating, runningGameID != game.id else { return }
        editing = true
        defer { editing = false }
        let updated = games.filter { $0.id != game.id }
        do {
            try await store.save(updated)
            games = updated
            playErrors[game.id] = nil
            error = nil
        } catch { self.error = InstalledGameError.storage.localizedDescription }
    }

    static func runID(date: Date = Date(), nonce: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let suffix = nonce.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        return "xodus-\(formatter.string(from: date))-\(suffix)"
    }

    static func launchEnvironment(_ inherited: [String: String]) -> [String: String] {
        var environment = inherited.filter { ["HOME", "USER", "LANG"].contains($0.key) }
        environment["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    func play(_ game: InstalledGame) async {
        guard loaded, !editing, !choosing, runningGameID == nil, !applicationTerminating,
              games.contains(game) else { return }
        let token = UUID()
        runToken = token
        runningGameID = game.id
        playState = .launching
        playErrors[game.id] = nil
        do {
            let environment = Self.launchEnvironment(ProcessInfo.processInfo.environment)
            let runID = Self.runID()
            let child = try await Task.detached(priority: .userInitiated) { [weak self] in
                try InstalledGameFiles.checkFolder(URL(fileURLWithPath: game.folder))
                try InstalledGameFiles.checkLauncher(URL(fileURLWithPath: game.launcher))
                let child = Process()
                child.executableURL = URL(fileURLWithPath: "/bin/bash")
                child.arguments = [game.launcher, runID]
                child.environment = environment
                child.standardInput = FileHandle.nullDevice
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                child.terminationHandler = { [weak self] value in
                    let status = value.terminationStatus
                    Task { @MainActor [weak self] in self?.finished(token: token, gameID: game.id, status: status) }
                }
                try child.run()
                return child
            }.value
            // A short-lived script can exit before the off-main launch returns.
            guard runToken == token else { return }
            process = child
            playingTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: self.launchingDuration) }
                catch { return }
                if self.runToken == token, child.isRunning { self.playState = .playing }
            }
        } catch {
            if runToken == token {
                finished(token: token, gameID: game.id, status: 0)
                playErrors[game.id] = (error as? InstalledGameError)?.localizedDescription
                    ?? InstalledGameError.launch.localizedDescription
            }
        }
    }

    private func finished(token: UUID, gameID: UUID, status: Int32) {
        guard runToken == token else { return }
        playingTask?.cancel()
        playingTask = nil
        process = nil
        runToken = nil
        runningGameID = nil
        playState = nil
        if status != 0 { playErrors[gameID] = "The game stopped unexpectedly (code \(status))." }
    }
}
