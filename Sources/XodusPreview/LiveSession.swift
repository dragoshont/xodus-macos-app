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
    @Published private(set) var catalogStopped = false
    @Published private(set) var accountBusy = false
    @Published private(set) var accountStatusCurrent = false
    @Published private(set) var lookupBusy = false
    @Published private(set) var installedSnapshot: InstalledSnapshot?
    @Published private(set) var installedRefreshing = false
    @Published private(set) var installedError: String?
    @Published private(set) var inspection: InstallationInspection?
    @Published private(set) var inspectionBusy = false
    @Published private(set) var inspectionError: String?
    @Published private(set) var nextCursor: String?
    @Published private(set) var catalogCorpus = "observedPublicProducts"
    @Published private(set) var discoveryFailures: [DiscoveryFailure] = []
    @Published private(set) var discoveryCheckedAt: String?
    @Published var selectedProduct: CatalogProduct?
    @Published var errorMessage: String?
    @Published var catalogError: String?
    @Published var backendPath: String
    @Published var market = "US" { didSet { if market != oldValue { invalidateCatalogScope() } } }
    @Published var language = "en-US" { didSet { if language != oldValue { invalidateCatalogScope() } } }
    @Published var lookupID = ""
    @Published var diagnosticPreview: String?
    private var client: ManagementClient?
    private var eventTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var generation = 0
    private var queryGeneration = 0
    private var authenticationGeneration = 0
    private var currentQuery = ""
    private var cacheRevision: UInt64?
    private var discoveryRevision: String?
    private let configuration: BackendConfiguration?
    private var signInDeadline: ContinuousClock.Instant?
    private var catalogTask: Task<Void, Never>?
    private var catalogWorkerID: UUID?
    private var queuedCatalog: CatalogRequest?

    private struct CatalogRequest {
        let command: ManagementCommand
        let query: String
        let market: String
        let language: String
        let cursor: String?
        let more: Bool
        let generation: Int
        let queryGeneration: Int
    }

    init(configuration: BackendConfiguration? = nil) {
        self.configuration = configuration
        if let configuration {
            backendPath = configuration.executable.path
            return
        }
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("XodusEngine/xodus-cli")
        let bundledPath = embedded.flatMap {
            FileManager.default.isExecutableFile(atPath: $0.path) ? $0.path : nil
        }
        if let override = ProcessInfo.processInfo.environment["XODUS_BACKEND_PATH"], !override.isEmpty {
            backendPath = override
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            backendPath = bundledPath ?? ""
            if bundledPath == nil {
                errorMessage = "This app's included Xodus engine is missing or not executable. Rebuild or reinstall the matching development app; Advanced Settings can explicitly select a trusted development engine."
            }
        } else {
            backendPath = bundledPath ?? UserDefaults.standard.string(forKey: "Xodus.developerBackendPath") ?? ""
        }
    }

    var isReady: Bool { phase == .ready }
    var signInPending: Bool { authentication?.flow?.state == .pending }
    var canSignIn: Bool {
        isReady && supports(.authBegin) && supports(.authCancel) && supports(.authStatus)
            && accountStatusCurrent && authentication?.state == .signedOut && !accountBusy && !signInPending
    }
    var needsAccountDisconnect: Bool {
        guard let state = authentication?.state else { return false }
        return [.credentialPresent, .expired, .invalid].contains(state)
    }
    var canDisconnectAccount: Bool {
        isReady && supports(.authLogout) && accountStatusCurrent && needsAccountDisconnect
            && !accountBusy && !signInPending
    }
    var canLoadMoreCatalog: Bool { nextCursor != nil && !searching }

    var accountLabel: String {
        if phase == .connecting { return "Connecting to Xodus" }
        guard isReady else { return "Connect Xodus" }
        if signInPending { return "Finish Microsoft sign-in" }
        switch authentication?.state {
        case .credentialPresent: return "Microsoft sign-in saved"
        case .expired: return "Sign-in expired"
        case .invalid: return "Sign-in needs attention"
        case .signedOut: return "Sign in with Microsoft"
        case nil: return "Account"
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
        guard await disconnect() else { return }
        phase = .connecting
        errorMessage = nil
        let token = generation
        do {
            let connection = try ManagementClient()
            client = connection
            let state = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/Xodus/Management", isDirectory: true)
            let negotiated = try await connection.connect(configuration ?? BackendConfiguration(
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
                        if event.data.state == .completed,
                           !["pcGamePassDiscovery", "publicMicrosoftStoreSearch"].contains(self.catalogCorpus) {
                            await self.search(self.currentQuery)
                        }
                    }
                } catch {
                    guard let self, token == self.generation else { return }
                    await self.connectionFailed(error)
                }
            }
            // Credential-store authorization belongs to explicit Account actions, not anonymous startup.
            await refreshInstalled()
            await search("")
        } catch {
            guard token == generation else { return }
            await connectionFailed(error)
        }
    }

    @discardableResult
    func disconnect() async -> Bool {
        generation += 1
        authenticationGeneration += 1
        queryGeneration += 1
        eventTask?.cancel()
        authTask?.cancel()
        catalogTask?.cancel()
        catalogTask = nil
        catalogWorkerID = nil
        queuedCatalog = nil
        eventTask = nil
        authTask = nil
        let previous = client
        client = nil
        hello = nil
        authentication = nil
        accountStatusCurrent = false
        signInDeadline = nil
        installedSnapshot = nil
        installedError = nil
        installedRefreshing = false
        inspection = nil
        inspectionBusy = false
        inspectionError = nil
        products = []
        selectedProduct = nil
        activity = ActivityStore()
        nextCursor = nil
        cacheRevision = nil
        catalogCorpus = "observedPublicProducts"
        discoveryFailures = []
        discoveryCheckedAt = nil
        discoveryRevision = nil
        diagnosticPreview = nil
        phase = .disconnected
        searching = false
        catalogStopped = false
        lookupBusy = false
        accountBusy = false
        if let previous, !(await previous.close()) {
            client = previous
            phase = .failed
            errorMessage = Self.describe(ManagementError.shutdownFailed)
            return false
        }
        return true
    }

    private func connectionFailed(_ error: Error) async {
        guard await disconnect() else { return }
        phase = .failed
        errorMessage = Self.describe(error)
    }

    func refreshAccount() async {
        guard isReady, supports(.authStatus), let client else { return }
        let token = generation
        authenticationGeneration += 1
        let authToken = authenticationGeneration
        do {
            let status = try await client.request(.authStatus).decode(AuthenticationStatus.self)
            guard token == generation, authToken == authenticationGeneration else { return }
            acceptAccountStatus(status)
            errorMessage = nil
        } catch {
            guard token == generation, authToken == authenticationGeneration else { return }
            accountStatusCurrent = false
            errorMessage = Self.describe(error)
        }
    }

    private func acceptAccountStatus(_ status: AuthenticationStatus) {
        if let currentFlow = authentication?.flow, let incomingFlow = status.flow,
           currentFlow.flowID == incomingFlow.flowID,
           currentFlow.state != .pending, incomingFlow.state == .pending { return }
        authentication = status
        accountStatusCurrent = true
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

    func chooseInstallationFolder() {
        guard isReady, supports(.inspectInstallation), !inspectionBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Inspect a game folder"
        panel.message = "Choose one exact folder. Xodus reads only its streaming marker metadata; it will not scan, register, modify or launch the game."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await inspectInstallation(at: url) }
    }

    func inspectInstallation(at directory: URL) async {
        guard isReady, supports(.inspectInstallation), let client, !inspectionBusy else { return }
        guard directory.isFileURL, directory.host == nil || directory.host == "",
              directory.path.hasPrefix("/") else {
            inspectionError = "Choose one local game folder. No files were inspected or changed."
            return
        }
        inspectionBusy = true
        inspection = nil
        inspectionError = nil
        let token = generation
        defer { if token == generation { inspectionBusy = false } }
        do {
            let result = try await client.request(.inspectInstallation, params: ["directory": .string(directory.path)])
                .decode(InstallationInspection.self)
            guard token == generation else { return }
            try result.validateSelection(directory: directory.path)
            inspection = result
        } catch {
            guard token == generation else { return }
            switch error {
            case ManagementError.backendError("NOT_FOUND", _):
                inspectionError = "This folder has no Xodus streaming marker. Nothing was added to your Library."
            case ManagementError.backendError("INTEGRITY_FAILED", _):
                inspectionError = "The marker could not be safely interpreted. No files were changed."
            case ManagementError.backendError("UNSUPPORTED_CONFIGURATION", _):
                inspectionError = "This folder cannot be safely inspected. Choose a direct local folder without aliases or linked files."
            default: inspectionError = Self.describe(error)
            }
        }
    }

    func beginSignIn() async {
        guard canSignIn, let client else { return }
        authenticationGeneration += 1
        accountBusy = true
        errorMessage = nil
        let token = generation
        do {
            let status = try await client.request(.authBegin, params: ["accountScope": .string("default")])
                .decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard let flow = status.flow else { throw ManagementError.invalidPayload }
            authentication = status
            accountStatusCurrent = true
            signInDeadline = ContinuousClock.now.advanced(by: .seconds(600))
            accountBusy = false
            if flow.state == .pending { pollSignIn(flowID: flow.flowID, generation: token) }
        } catch {
            guard token == generation else { return }
            accountBusy = false
            accountStatusCurrent = false
            errorMessage = Self.describe(error)
        }
    }

    private func pollSignIn(flowID: String, generation token: Int) {
        authTask?.cancel()
        authTask = Task { [weak self] in
            let deadline = self?.signInDeadline ?? ContinuousClock.now.advanced(by: .seconds(600))
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1))
                    guard let self, token == self.generation, let client = self.client else { return }
                    guard ContinuousClock.now < deadline else {
                        self.errorMessage = "Sign-in is still pending. Check status before retrying or closing; no cancellation was assumed."
                        return
                    }
                    let status: AuthenticationStatus
                    do { status = try await client.request(.authStatus).decode(AuthenticationStatus.self) }
                    catch {
                        guard token == self.generation, !Task.isCancelled else { return }
                        self.accountStatusCurrent = false
                        self.errorMessage = Self.describe(error)
                        if error as? ManagementError == .credentialStoreUnavailable { continue }
                        if case ManagementError.backendError(_, retryable: true) = error { continue }
                        return
                    }
                    guard token == self.generation, !Task.isCancelled,
                          self.authentication?.flow?.flowID == flowID,
                          self.authentication?.flow?.state == .pending else { return }
                    guard status.flow?.flowID == flowID else { throw ManagementError.invalidPayload }
                    self.acceptAccountStatus(status)
                    if status.flow?.state != .pending {
                        if status.flow?.state == .completed { self.errorMessage = nil }
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
        authenticationGeneration += 1
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
            accountStatusCurrent = true
            if status.flow?.state == .completed {
                errorMessage = "Sign-in finished before cancellation. Your sign-in is saved; use Sign out to remove it."
            }
        } catch {
            guard token == generation else { return }
            if case ManagementError.backendError("INVALID_TRANSITION", _) = error {
                errorMessage = "Sign-in is finishing. Checking the saved result before closing."
            } else { errorMessage = Self.describe(error) }
            if authentication?.flow?.flowID == flow.flowID, signInPending {
                pollSignIn(flowID: flow.flowID, generation: token)
            }
        }
        if token == generation { accountBusy = false }
    }

    func signOut() async {
        guard let client, canDisconnectAccount else {
            errorMessage = "Check the current saved sign-in before disconnecting. No credentials were removed."
            return
        }
        authenticationGeneration += 1
        accountBusy = true
        authTask?.cancel()
        authentication = nil
        accountStatusCurrent = false
        selectedProduct = nil
        products = []
        nextCursor = nil
        let token = generation
        do {
            let status = try await client.request(.authLogout).decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard status.state == .signedOut else { throw ManagementError.invalidPayload }
            authentication = status
            accountStatusCurrent = true
            diagnosticPreview = nil
            await refreshCatalog(currentQuery)
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
        }
        if token == generation { accountBusy = false }
    }

    func search(_ query: String, more: Bool = false) async {
        await queueCatalog(query, command: .search, more: more)
    }

    private func queueCatalog(_ query: String, command: ManagementCommand, more: Bool) async {
        guard isReady, supports(command) else { return }
        guard validScope else { catalogError = "Use a two-letter market and a language such as en-US."; return }
        let corpus = command == .query ? "publicMicrosoftStoreSearch"
            : command == .discover ? "pcGamePassDiscovery" : "observedPublicProducts"
        if more && (searching || nextCursor == nil || catalogCorpus != corpus || currentQuery != query) { return }
        queryGeneration += 1
        queuedCatalog = CatalogRequest(command: command, query: query, market: market, language: language,
            cursor: more ? nextCursor : nil, more: more, generation: generation, queryGeneration: queryGeneration)
        currentQuery = query
        if !more {
            products = []
            nextCursor = nil
            cacheRevision = nil
            discoveryFailures = []
            discoveryCheckedAt = nil
            discoveryRevision = nil
        }
        catalogCorpus = corpus
        searching = true
        catalogStopped = false
        catalogError = nil
        if catalogTask == nil {
            let workerID = UUID()
            catalogWorkerID = workerID
            catalogTask = Task { [weak self] in
                guard let self else { return }
                // Cancelling a view task does not release a producer HTTP operation.
                while !Task.isCancelled, self.catalogWorkerID == workerID,
                      let request = self.queuedCatalog {
                    self.queuedCatalog = nil
                    switch request.command {
                    case .query: await self.queryStore(request)
                    case .discover: await self.browseDiscovery(request)
                    default: await self.searchCache(request)
                    }
                }
                if self.catalogWorkerID == workerID {
                    self.catalogTask = nil
                    self.catalogWorkerID = nil
                }
            }
        }
        await catalogTask?.value
    }

    private func isCurrent(_ request: CatalogRequest) -> Bool {
        request.generation == generation && request.queryGeneration == queryGeneration && !Task.isCancelled
    }

    private func searchCache(_ request: CatalogRequest) async {
        guard let client, request.generation == generation else { return }
        defer { if isCurrent(request) { searching = false } }
        do {
            let result = try await client.request(.search, params: [
                "query": .string(request.query), "market": .string(request.market), "language": .string(request.language),
                "platform": .string("pc"), "limit": .integer(100), "cursor": request.cursor.map(JSONValue.string) ?? .null
            ]).decode(CatalogSearch.self)
            guard isCurrent(request) else { return }
            guard Set(result.products.map(\.id)).count == result.products.count else {
                throw ManagementError.invalidPayload
            }
            for product in result.products {
                try product.validatePublicScope(market: request.market, language: request.language)
            }
            if request.more {
                guard result.cacheRevision == cacheRevision,
                      Set(products.map(\.id)).isDisjoint(with: Set(result.products.map(\.id))),
                      products.count + result.products.count <= 512 else {
                    throw ManagementError.backendError("REVISION_CONFLICT", retryable: true)
                }
                products += result.products
            } else { products = result.products }
            cacheRevision = result.cacheRevision
            nextCursor = result.nextCursor
            catalogCorpus = result.corpus
            discoveryFailures = []
            discoveryCheckedAt = nil
            discoveryRevision = nil
        } catch {
            guard isCurrent(request) else { return }
            catalogError = Self.describe(error)
        }
    }

    func refreshCatalog(_ query: String, more: Bool = false) async {
        let scopedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if scopedQuery.isEmpty, supports(.discover) {
            await queueCatalog(scopedQuery, command: .discover, more: more)
        } else if !scopedQuery.isEmpty, supports(.query) {
            await queueCatalog(scopedQuery, command: .query, more: more)
        } else { await search(scopedQuery, more: more) }
    }

    func stopCatalogSearch() {
        guard searching else { return }
        queryGeneration += 1
        queuedCatalog = nil
        searching = false
        catalogStopped = true
        catalogError = nil
    }

    private func queryStore(_ request: CatalogRequest) async {
        guard let client, request.generation == generation else { return }
        defer { if isCurrent(request) { searching = false } }
        do {
            let page = try await client.request(.query, params: [
                "query": .string(request.query), "market": .string(request.market), "language": .string(request.language),
                "limit": .integer(8), "cursor": request.cursor.map(JSONValue.string) ?? .null
            ], timeout: .seconds(45)).decode(CatalogQuery.self)
            guard isCurrent(request) else { return }
            try applyQueryPage(page, request: request)
        } catch {
            guard isCurrent(request) else { return }
            if case let ManagementError.queryFailed(page) = error {
                do { try applyQueryPage(page, request: request) }
                catch { catalogError = Self.describe(error); return }
            }
            catalogError = Self.describe(error)
        }
    }

    private func applyQueryPage(_ page: CatalogQuery, request: CatalogRequest) throws {
        try page.validatePublicScope(query: request.query, market: request.market, language: request.language, limit: 8)
        let existingIDs = Set(products.map(\.id) + discoveryFailures.map(\.id))
        let incomingIDs = Set(page.products.map(\.id) + page.failures.map(\.id))
        if request.more {
            guard existingIDs.isDisjoint(with: incomingIDs), existingIDs.count + incomingIDs.count <= 512,
                  page.nextCursor != request.cursor else {
                throw ManagementError.backendError("REVISION_CONFLICT", retryable: true)
            }
            products += page.products
            discoveryFailures += page.failures
        } else {
            products = page.products
            discoveryFailures = page.failures
        }
        nextCursor = page.nextCursor
        discoveryCheckedAt = page.checkedAt
        catalogCorpus = page.corpus
    }

    private func browseDiscovery(_ request: CatalogRequest) async {
        guard let client, request.generation == generation else { return }
        defer { if isCurrent(request) { searching = false } }
        do {
            let page = try await client.request(.discover, params: [
                "market": .string(request.market), "language": .string(request.language), "limit": .integer(8),
                "cursor": request.cursor.map(JSONValue.string) ?? .null
            ], timeout: .seconds(45)).decode(CatalogDiscovery.self)
            guard isCurrent(request) else { return }
            try applyDiscoveryPage(page, request: request)
        } catch {
            guard isCurrent(request) else { return }
            if case let ManagementError.discoveryFailed(page) = error {
                do { try applyDiscoveryPage(page, request: request) }
                catch { catalogError = Self.describe(error); return }
            }
            catalogError = Self.describe(error)
        }
    }

    private func applyDiscoveryPage(_ page: CatalogDiscovery, request: CatalogRequest) throws {
        try page.validatePublicScope(market: request.market, language: request.language, limit: 8)
        let existingIDs = Set(products.map(\.id) + discoveryFailures.map(\.id))
        let incomingIDs = Set(page.products.map(\.id) + page.failures.map(\.id))
        if request.more {
            guard page.corpusRevision == discoveryRevision, existingIDs.isDisjoint(with: incomingIDs),
                  existingIDs.count + incomingIDs.count <= 512, page.nextCursor != request.cursor else {
                throw ManagementError.backendError("REVISION_CONFLICT", retryable: true)
            }
            products += page.products
            discoveryFailures += page.failures
        } else {
            products = page.products
            discoveryFailures = page.failures
        }
        nextCursor = page.nextCursor
        discoveryRevision = page.corpusRevision
        discoveryCheckedAt = page.checkedAt
        catalogCorpus = page.corpus
        cacheRevision = nil
    }

    private func invalidateCatalogScope() {
        queryGeneration += 1
        queuedCatalog = nil
        products = []
        selectedProduct = nil
        nextCursor = nil
        cacheRevision = nil
        discoveryRevision = nil
        discoveryFailures = []
        discoveryCheckedAt = nil
        catalogCorpus = "observedPublicProducts"
        catalogError = nil
        searching = false
        catalogStopped = false
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
            case "AUTH_INVALID": return "The saved sign-in could not be validated. Check status before disconnecting and reconnecting it."
            case "AUTH_REQUIRED": return "Sign in with Microsoft before continuing."
            case "AUTH_EXPIRED": return "Your saved sign-in expired. Check status, then disconnect it before signing in again."
            case "CURSOR_INVALID", "REVISION_CONFLICT":
                return "The catalog changed while browsing. Refresh this scope before loading more."
            default: break
            }
        }
        return (error as? ManagementError)?.localizedDescription ?? "The connection could not complete. Reconnect to try again."
    }
}
