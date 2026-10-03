// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import XodusManagement

enum ConnectionPhase { case disconnected, connecting, ready, failed }

@MainActor
final class LiveSession: ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .disconnected
    @Published private(set) var hello: ManagementHello?
    @Published private(set) var authentication: AuthenticationStatus?
    @Published private(set) var products: [CatalogProduct] = []
    @Published private(set) var activity = ActivityStore()
    @Published private(set) var searching = false
    @Published private(set) var accountBusy = false
    @Published private(set) var lookupBusy = false
    @Published private(set) var installedSnapshot: InstalledSnapshot?
    @Published private(set) var installedRefreshing = false
    @Published private(set) var installedError: String?
    @Published private(set) var nextCursor: String?
    @Published var selectedProduct: CatalogProduct?
    @Published var errorMessage: String?
    @Published var catalogError: String?
    @Published var backendPath: String
    @Published var market = "US"
    @Published var language = "en-US"
    @Published var lookupID = ""
    @Published var diagnosticPreview: String?
    private var client: ManagementClient?
    private var eventTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var generation = 0
    private var queryGeneration = 0
    private var currentQuery = ""
    private var cacheRevision: UInt64?

    init() {
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("XodusEngine/xodus-cli")
        let bundledPath = embedded.flatMap {
            FileManager.default.isExecutableFile(atPath: $0.path) ? $0.path : nil
        }
        backendPath = ProcessInfo.processInfo.environment["XODUS_BACKEND_PATH"]
            ?? bundledPath
            ?? UserDefaults.standard.string(forKey: "Xodus.developerBackendPath") ?? ""
    }

    var isReady: Bool { phase == .ready }
    var signInPending: Bool { authentication?.flow?.state == .pending }
    var canSignIn: Bool {
        isReady && supports(.authBegin) && supports(.authCancel) && supports(.authStatus)
            && !accountBusy && !signInPending
    }

    var accountLabel: String {
        if phase == .connecting { return "Connecting to Xodus" }
        guard isReady else { return "Connect Xodus" }
        if signInPending { return "Finish Microsoft sign-in" }
        switch authentication?.state {
        case .credentialPresent: return "Xbox sign-in saved"
        case .expired: return "Sign-in expired"
        case .invalid: return "Sign-in needs attention"
        case .signedOut: return "Sign in to Xbox"
        case nil: return "Account status unavailable"
        }
    }

    func supports(_ command: ManagementCommand) -> Bool { hello?.supports(command) == true }

    func chooseBackend() {
        let panel = NSOpenPanel()
        panel.title = "Choose a trusted Xodus management build"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            errorMessage = "That file is not executable. Choose the Xodus management engine."
            return
        }
        backendPath = url.path
        UserDefaults.standard.set(url.path, forKey: "Xodus.developerBackendPath")
    }

    func connect() async {
        guard phase != .connecting, !backendPath.isEmpty else {
            if backendPath.isEmpty { errorMessage = "Choose your trusted Xodus build in Settings first." }
            return
        }
        await disconnect()
        phase = .connecting
        errorMessage = nil
        let token = generation
        do {
            let connection = try ManagementClient()
            client = connection
            let state = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/Xodus/Management", isDirectory: true)
            let negotiated = try await connection.connect(BackendConfiguration(
                executable: URL(fileURLWithPath: backendPath), stateDirectory: state))
            guard token == generation else { await connection.close(); return }
            hello = negotiated
            phase = .ready
            if supports(.jobs) { try await reconcileActivity() }
            eventTask = Task { [weak self] in
                do {
                    for try await event in connection.events {
                        guard let self, token == self.generation else { return }
                        try self.activity.apply(event)
                        if self.activity.needsSnapshot && !self.activity.isReconciling {
                            try await self.reconcileActivity()
                        }
                        if event.data.state == .completed { await self.search(self.currentQuery) }
                    }
                } catch {
                    guard let self, token == self.generation else { return }
                    await self.connectionFailed(error)
                }
            }
            await refreshAccount()
            await refreshInstalled()
            await search("")
        } catch {
            guard token == generation else { return }
            await connectionFailed(error)
        }
    }

    func disconnect() async {
        generation += 1
        queryGeneration += 1
        eventTask?.cancel()
        authTask?.cancel()
        eventTask = nil
        authTask = nil
        let previous = client
        client = nil
        hello = nil
        authentication = nil
        installedSnapshot = nil
        installedError = nil
        installedRefreshing = false
        products = []
        selectedProduct = nil
        activity = ActivityStore()
        nextCursor = nil
        cacheRevision = nil
        diagnosticPreview = nil
        phase = .disconnected
        searching = false
        lookupBusy = false
        accountBusy = false
        if let previous { await previous.close() }
    }

    private func connectionFailed(_ error: Error) async {
        await disconnect()
        phase = .failed
        errorMessage = Self.describe(error)
    }

    func refreshAccount() async {
        guard isReady, supports(.authStatus), let client else { return }
        let token = generation
        do {
            let status = try await client.request(.authStatus).decode(AuthenticationStatus.self)
            guard token == generation else { return }
            authentication = status
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
    }

    func refreshInstalled() async {
        guard isReady, supports(.installed), let client, !installedRefreshing else { return }
        let token = generation
        installedRefreshing = true
        installedError = nil
        defer { if token == generation { installedRefreshing = false } }
        do {
            let snapshot = try await client.request(.installed).decode(InstalledSnapshot.self)
            guard token == generation else { return }
            guard snapshot.scope == "managementRegistryOnly", snapshot.completeness == "complete",
                  Set(snapshot.installations.map(\.id)).count == snapshot.installations.count,
                  installedSnapshot.map({ snapshot.watermark >= $0.watermark }) ?? true else {
                throw ManagementError.invalidPayload
            }
            installedSnapshot = snapshot
        } catch {
            guard token == generation else { return }
            installedSnapshot = nil
            installedError = Self.describe(error)
        }
    }

    func installationTitle(_ installation: RegisteredInstallation) -> String {
        products.first { $0.id == installation.productID }?.title ?? "Product \(installation.productID)"
    }

    func beginSignIn() async {
        guard canSignIn, let client else { return }
        accountBusy = true
        errorMessage = nil
        let token = generation
        do {
            let status = try await client.request(.authBegin, params: ["accountScope": .string("default")])
                .decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard let flow = status.flow else { throw ManagementError.invalidPayload }
            authentication = status
            accountBusy = false
            if flow.state == .pending { pollSignIn(flowID: flow.flowID, generation: token) }
        } catch {
            guard token == generation else { return }
            accountBusy = false
            errorMessage = Self.describe(error)
        }
    }

    private func pollSignIn(flowID: String, generation token: Int) {
        authTask?.cancel()
        authTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(600)
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1))
                    guard let self, token == self.generation, let client = self.client else { return }
                    let status = try await client.request(.authStatus).decode(AuthenticationStatus.self)
                    guard token == self.generation, !Task.isCancelled,
                          self.authentication?.flow?.flowID == flowID else { return }
                    guard status.flow?.flowID == flowID else { throw ManagementError.invalidPayload }
                    self.authentication = status
                    if status.flow?.state != .pending { return }
                    if Date() >= deadline {
                        await self.cancelSignIn()
                        self.errorMessage = "Sign-in timed out. Start again when you are ready."
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, token == self.generation else { return }
                self.errorMessage = Self.describe(error)
            }
        }
    }

    func cancelSignIn() async {
        guard let flow = authentication?.flow, flow.state == .pending, let client,
              supports(.authCancel), !accountBusy else { return }
        accountBusy = true
        authTask?.cancel()
        let token = generation
        do {
            let status = try await client.request(.authCancel, params: ["flowID": .string(flow.flowID)])
                .decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard status.flow?.flowID == flow.flowID, status.flow?.state != .pending else {
                throw ManagementError.invalidPayload
            }
            authentication = status
            if status.flow?.state == .completed {
                errorMessage = "Sign-in finished before cancellation. Your sign-in is saved; use Sign out to remove it."
            }
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
        if token == generation { accountBusy = false }
    }

    func signOut() async {
        guard let client, isReady, supports(.authLogout), !accountBusy else { return }
        accountBusy = true
        authTask?.cancel()
        authentication = nil
        selectedProduct = nil
        products = []
        nextCursor = nil
        let token = generation
        do {
            let status = try await client.request(.authLogout).decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard status.state == .signedOut else { throw ManagementError.invalidPayload }
            authentication = status
            diagnosticPreview = nil
            await search(currentQuery)
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
        if token == generation { accountBusy = false }
    }

    func search(_ query: String, more: Bool = false) async {
        guard isReady, supports(.search), let client else { return }
        guard validScope else { catalogError = "Use a two-letter market and a language such as en-US."; return }
        queryGeneration += 1
        let searchToken = queryGeneration, token = generation
        defer {
            if token == generation, searchToken == queryGeneration { searching = false }
        }
        currentQuery = query
        searching = true
        catalogError = nil
        do {
            let cursor: JSONValue = more ? nextCursor.map(JSONValue.string) ?? .null : .null
            let result = try await client.request(.search, params: [
                "query": .string(query), "market": .string(market), "language": .string(language),
                "platform": .string("pc"), "limit": .integer(100), "cursor": cursor
            ]).decode(CatalogSearch.self)
            guard token == generation, searchToken == queryGeneration, !Task.isCancelled else { return }
            guard result.products.allSatisfy({ product in
                product.market == market && product.language.caseInsensitiveCompare(language) == .orderedSame
                    && product.pcCatalogCandidate && product.source != "fixture"
                    && Set(product.editions.map(\.id)).count == product.editions.count
                    && product.editions.allSatisfy {
                        $0.productID == product.id && $0.entitlement.kind == .unknown
                    }
            }) else {
                throw ManagementError.invalidPayload
            }
            if more {
                guard result.cacheRevision == cacheRevision,
                      Set(products.map(\.id)).isDisjoint(with: Set(result.products.map(\.id))) else {
                    throw ManagementError.backendError("REVISION_CONFLICT", retryable: true)
                }
                products += result.products
            } else { products = result.products }
            cacheRevision = result.cacheRevision
            nextCursor = result.nextCursor
        } catch {
            guard token == generation, searchToken == queryGeneration else { return }
            catalogError = Self.describe(error)
        }
    }

    func lookupProduct() async {
        guard isReady, let client, supports(.enqueue), !lookupBusy else { return }
        guard validScope else {
            errorMessage = "Use a two-letter market and a language such as en-US."
            return
        }
        let id = lookupID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard id.range(of: "^[A-Z0-9]{12}$", options: .regularExpression) != nil else {
            errorMessage = "Enter a 12-character public Microsoft Store product ID."
            return
        }
        lookupBusy = true
        errorMessage = nil
        let token = generation
        do {
            let result = try await client.request(.enqueue, params: [
                "kind": .string("catalogRefresh"), "idempotencyKey": .string(UUID().uuidString),
                "product": .object(["productID": .string(id), "market": .string(market),
                                    "language": .string(language), "refresh": .string("network")])
            ]).decode(JobResult.self)
            guard token == generation else { return }
            guard result.job.product.productID == id else { throw ManagementError.invalidPayload }
            try await reconcileActivity()
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
        if token == generation { lookupBusy = false }
    }

    func changeJob(_ job: CatalogJob, command: ManagementCommand) async {
        guard isReady, let client, supports(command), !activity.needsSnapshot, !activity.isReconciling else { return }
        let token = generation
        do {
            _ = try await client.request(command, params: [
                "jobID": .string(job.id), "expectedRevision": .unsigned(job.revision)
            ]).decode(JobResult.self)
            guard token == generation else { return }
            try await reconcileActivity()
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
    }

    func reconcileActivity() async throws {
        guard supports(.jobs), let client, !activity.isReconciling else { return }
        let token = generation
        for _ in 0..<3 {
            try activity.beginSnapshot()
            do {
                let snapshot = try await client.request(.jobs).decode(JobsSnapshot.self)
                guard token == generation else { return }
                guard snapshot.sessionID == hello?.sessionID else { throw ManagementError.invalidEvent }
                try activity.apply(snapshot)
                if !activity.needsSnapshot { return }
            } catch {
                guard token == generation else { return }
                // A failed fence must not leave the UI waiting indefinitely for a snapshot.
                activity.abortSnapshot()
                throw error
            }
        }
        throw ManagementError.invalidEvent
    }

    func previewDiagnostics() async {
        guard supports(.diagnostics), let client else { return }
        let token = generation
        do {
            let value = try await client.request(.diagnostics)
            guard token == generation else { return }
            guard let jobs = value["jobCount"]?.uint64, let products = value["cachedProductCount"]?.uint64,
                  value["redacted"] == .bool(true) else { throw ManagementError.invalidPayload }
            diagnosticPreview = "Management protocol 1.0\nCatalog checks: \(jobs)\nCached public products: \(products)\nRuntime certified: no\nOwned-PC inventory authorized: no\nNo account identifiers, tokens, URLs or raw engine logs included."
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
    }

    private var validScope: Bool {
        market.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil
            && language.range(of: "^[a-z]{2,3}(-[A-Z]{2})?$", options: .regularExpression) != nil
    }

    static func describe(_ error: Error) -> String {
        if case let ManagementError.backendError(code, _) = error {
            switch code {
            case "AUTH_INVALID": return "The saved sign-in could not be validated. Sign in again to repair it."
            case "AUTH_REQUIRED": return "Sign in with Microsoft before continuing."
            case "AUTH_EXPIRED": return "Your saved sign-in expired. Sign in again."
            case "CURSOR_INVALID", "REVISION_CONFLICT":
                return "The catalog changed while browsing. Refresh this scope before loading more."
            default: break
            }
        }
        return (error as? ManagementError)?.localizedDescription ?? "The connection could not complete. Reconnect to try again."
    }
}
