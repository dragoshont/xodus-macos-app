// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation

@MainActor
final class PCGamesController: ObservableObject {
    @Published private(set) var hasSavedSignIn = false
    @Published private(set) var needsSignIn = false
    @Published private(set) var busy = false
    @Published private(set) var sheetPresented = false
    @Published private(set) var deviceCode: PCGamesDeviceCode?
    @Published private(set) var snapshot: PCGamesSnapshot?
    @Published private(set) var error: String?
    private let store: any PCGamesRefreshStore
    private let client: PCGamesClient
    private let market: String
    private let language: String
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var restored = false
    private var terminating = false

    init(store: any PCGamesRefreshStore = PCGamesKeychain(), client: PCGamesClient = PCGamesClient(),
         market: String = PCGamesClient.market(Locale.current.region?.identifier),
         language: String = PCGamesClient.language(Locale.preferredLanguages.first ?? "en-US")) {
        self.store = store
        self.client = client
        self.market = market
        self.language = language
    }

    func restorePresence() async {
        guard !restored, !busy, !terminating else { return }
        restored = true
        let token = generation
        do {
            let present = try await store.contains()
            guard generation == token, !terminating else { return }
            hasSavedSignIn = present
        } catch {
            guard generation == token, !terminating else { return }
            self.error = Self.message(error)
        }
    }

    func signIn() {
        guard !busy, !terminating else { return }
        let token = UUID()
        generation = token
        busy = true
        error = nil
        deviceCode = nil
        snapshot = nil
        sheetPresented = true
        operation = Task {
            defer { finish(token) }
            do {
                let code = try await client.deviceCode()
                try current(token)
                deviceCode = code
                let tokens = try await client.poll(code)
                try current(token)
                try await store.save(tokens.refresh)
                try current(token)
                hasSavedSignIn = true
                needsSignIn = false
                sheetPresented = false
                deviceCode = nil
                let result = try await client.library(accessToken: tokens.access, market: market, language: language)
                try current(token)
                snapshot = result
            } catch is CancellationError { }
            catch {
                guard generation == token, !terminating else { return }
                self.error = Self.message(error)
            }
        }
    }

    func refresh() {
        guard !busy, hasSavedSignIn, !needsSignIn, !terminating else { return }
        let token = UUID()
        generation = token
        busy = true
        error = nil
        operation = Task {
            defer { finish(token) }
            do {
                guard let saved = try await store.read() else { throw PCGamesError.signInRequired }
                try current(token)
                let tokens = try await client.refresh(saved)
                try current(token)
                try await store.save(tokens.refresh)
                try current(token)
                let result = try await client.library(accessToken: tokens.access, market: market, language: language)
                try current(token)
                snapshot = result
            } catch is CancellationError { }
            catch {
                guard generation == token, !terminating else { return }
                if error as? PCGamesError == .signInRequired { needsSignIn = true }
                self.error = Self.message(error)
            }
        }
    }

    func cancelSignIn() async {
        guard sheetPresented else { return }
        let old = operation
        generation = UUID()
        old?.cancel()
        sheetPresented = false
        deviceCode = nil
        await old?.value
        operation = nil
        busy = false
        error = nil
    }

    func signOut() async {
        guard !terminating else { return }
        let old = operation
        generation = UUID()
        old?.cancel()
        busy = true
        sheetPresented = false
        deviceCode = nil
        await old?.value
        operation = nil
        do {
            try await store.delete()
            hasSavedSignIn = false
            needsSignIn = false
            snapshot = nil
            error = nil
        } catch { self.error = Self.message(error) }
        busy = false
    }

    func openVerification() {
        guard let code = deviceCode else { return }
        if !NSWorkspace.shared.open(code.verificationURL) {
            error = "Couldn't open your browser. Go to microsoft.com/link and enter the code."
        }
    }

    func beginTermination() {
        terminating = true
        generation = UUID()
        operation?.cancel()
        sheetPresented = false
        deviceCode = nil
        busy = false
    }

    func resumeAfterTerminationRefusal() { terminating = false }

    func waitForOperation() async { await operation?.value }

    private func current(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token, !terminating else { throw CancellationError() }
    }

    private func finish(_ token: UUID) {
        guard generation == token else { return }
        busy = false
        operation = nil
    }

    private static func message(_ error: Error) -> String {
        (error as? PCGamesError)?.localizedDescription ?? PCGamesError.transport.localizedDescription
    }

    static func installedMatch(_ game: PCGame, in installed: [InstalledGame]) -> InstalledGame? {
        installed.first { $0.storeId == game.id }
    }
}
