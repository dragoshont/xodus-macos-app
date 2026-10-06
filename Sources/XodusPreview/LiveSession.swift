// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import UniformTypeIdentifiers
import XodusManagement

enum ConnectionPhase { case disconnected, connecting, disconnecting, ready, failed }
private enum AccountAction { case status, signIn, cancellation, signOut }

@MainActor
final class LiveSession: ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .disconnected
    @Published private(set) var connectionTransitioning = false
    var applicationTerminating = false
    @Published private(set) var hello: ManagementHello?
    @Published private(set) var authentication: AuthenticationStatus?
    @Published private(set) var products: [CatalogProduct] = []
    @Published private(set) var activity = ActivityStore()
    @Published private(set) var searching = false
    @Published private(set) var catalogStopped = false
    @Published private(set) var accountBusy = false
    @Published private(set) var accountStatusChecking = false
    @Published private(set) var accountStatusCurrent = false
    @Published private(set) var accountError: String?
    @Published private(set) var accountStatusError: ManagementError?
    @Published private(set) var lastSignInFailure: SignInFailureSnapshot?
    @Published private(set) var activityError: String?
    @Published private(set) var lookupBusy = false
    @Published private(set) var installedSnapshot: InstalledSnapshot?
    @Published private(set) var installedSnapshotCurrent = false
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
    @Published private(set) var backendPath: String
    @Published var market = "US" { didSet { if market != oldValue { invalidateCatalogScope() } } }
    @Published var language = "en-US" { didSet { if language != oldValue { invalidateCatalogScope() } } }
    @Published var lookupID = ""
    @Published private(set) var diagnosticPreview: String?
    @Published private(set) var diagnosticPreviewing = false
    @Published private(set) var diagnosticSaving = false
    @Published private(set) var diagnosticSaved = false
    @Published private(set) var diagnosticExportError: String?
    private var client: ManagementClient?
    private var failedAccountAction: AccountAction?
    private var lifecycleRevision = 0
    private var connectOperationID: UUID?
    private var disconnectWaiters = 0
    private var closingOperation: ClosingOperation?
    private let shutdownClient: @Sendable (ManagementClient) async -> Bool
    private var eventTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var generation = 0
    private var queryGeneration = 0
    private var authenticationGeneration = 0
    private var currentQuery = ""
    private var cacheRevision: UInt64?
    private var discoveryRevision: String?
    private let configuration: BackendConfiguration?
    private let signInPollingBudget: Duration
    private var signInDeadline: ContinuousClock.Instant?
    private var catalogTask: Task<Void, Never>?
    private var catalogWorkerID: UUID?
    private var queuedCatalog: CatalogRequest?

    struct SignInFailureSnapshot: Equatable {
        enum Code: String {
            case invalid = "AUTH_INVALID", cancelled = "AUTH_CANCELLED"
            case expired = "AUTH_EXPIRED", networkUnavailable = "NETWORK_UNAVAILABLE"
        }

        let code: Code?
        let diagnostic: NativeConsentFailure?
        let observation: String?

        init(_ failure: WireFailure?) {
            code = failure.flatMap { Code(rawValue: $0.code) }
            diagnostic = failure?.nativeConsentFailure
            observation = failure.flatMap(LiveSession.validatedNativeSignInObservation)
        }

        init(requestError: Error) {
            if case let ManagementError.backendError(value, _) = requestError {
                code = Code(rawValue: value)
            } else { code = nil }
            diagnostic = nil
            observation = nil
        }
    }

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

    private struct ClosingOperation {
        let id: UUID
        let client: ManagementClient
        let task: Task<Bool, Never>
    }

    init(configuration: BackendConfiguration? = nil,
         signInPollingBudget: Duration = .seconds(600),
         shutdownClient: @escaping @Sendable (ManagementClient) async -> Bool = { await $0.close() }) {
        self.shutdownClient = shutdownClient
        self.signInPollingBudget = signInPollingBudget
#if XODUS_SHIPPING
        self.configuration = nil
        backendPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/XodusEngine/xodus-cli").path
        if ShippingPairPins.approved == nil {
            errorMessage = ManagementError.pairedEngineUnavailable.localizedDescription
        }
        return
#else
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
#endif
    }

    var isReady: Bool { phase == .ready }
    var signInPending: Bool { authentication?.flow?.state == .pending }
    var canSignIn: Bool {
        isReady && supports(.authBegin) && supports(.authCancel) && supports(.authStatus)
            && accountStatusCurrent && authentication?.state == .signedOut && !accountBusy && !signInPending
    }
    var accountNoticeTitle: String {
        if accountStatusChecking { return "Checking saved sign-in" }
        guard isReady, accountStatusCurrent else { return accountLabel }
        if authentication?.flow?.state == .failed { return "Sign-in failed" }
        if authentication?.flow?.state == .cancelled { return "Sign-in cancelled" }
        return accountLabel
    }
    var accountMessage: String {
        if phase == .connecting { return "Connecting to Xodus." }
        guard isReady else { return "Xodus couldn't connect. Open Settings to reconnect." }
        if accountStatusChecking {
            return "If macOS asks for Keychain access, respond in its permission window. Your saved sign-in is not being replaced."
        }
        if accountError != nil {
            if failedAccountAction == .status && accountStatusError == .credentialStoreUnavailable {
                return "Your saved sign-in couldn't be checked because Xodus cannot access Keychain. Sign-in stays disabled until access is confirmed. After resolving Keychain access, choose Check status."
            }
            switch failedAccountAction {
            case .status: return "Account status couldn't be checked. Choose Check status to try again."
            case .signIn: return "Sign-in couldn't be confirmed. Check status before trying again."
            case .cancellation: return "Cancellation couldn't be confirmed. Check status before trying again."
            case .signOut: return "Sign-out couldn't be confirmed. Check status before trying again."
            case nil: return "The account action couldn't be confirmed. Check status before trying again."
            }
        }
        if signInPending {
            return accountStatusCurrent
                ? "Continue in Microsoft's window if it opened, or cancel sign-in."
                : "Sign-in's current result is unknown. Check status before trying again."
        }
        guard accountStatusCurrent else { return "Check status to see whether you're signed in." }
        if authentication?.flow?.state == .failed {
            return "This sign-in didn't finish. Check Account info or try again when you're ready. You can still browse games."
        }
        if authentication?.flow?.state == .cancelled { return "You can sign in whenever you're ready." }
        switch currentCredentialState {
        case .credentialPresent: return "You're signed in. Library syncing isn't available yet."
        case .expired, .invalid: return "Disconnect this sign-in, then sign in again."
        case .signedOut: return "Connect your Microsoft account. You can browse games without signing in."
        case nil: return "Check status to see whether you're signed in."
        }
    }
    var libraryTitle: String {
        guard isReady else { return phase == .connecting ? "Connecting" : "Xodus couldn't connect" }
        return "Your Library isn't available yet"
    }
    var libraryMessage: String {
        guard isReady else { return "You can reconnect in Settings." }
        return "Xodus can't list your owned or installed games yet. Browse Discover, or check a folder you choose."
    }
    var activityNotice: String? {
        guard activityError != nil else { return nil }
        return "Activity couldn't be updated. Choose Refresh activity to check the latest result."
    }
    func productSummary(_ product: CatalogProduct) -> String {
        guard !product.editions.isEmpty else { return "Game information hasn't been resolved." }
        let access = Set(product.editions.map(\.entitlement.kind))
        let compatibility = Set(product.editions.map(\.compatibility.kind))
        if access == [.unknown] && compatibility == [.unknown] {
            return "Access and Mac compatibility haven't been checked. Install and Play aren't available yet."
        }
        let accessLabel = access.count == 1 ? product.editions[0].entitlement.kind.label : "Varies by edition"
        let compatibilityLabel = compatibility.count == 1 ? product.editions[0].compatibility.kind.label : "Varies by edition"
        return "Access: \(accessLabel). Mac compatibility: \(compatibilityLabel). Install and Play aren't available yet."
    }
    var catalogNotice: String? {
        if catalogStopped { return "Search stopped." }
        if catalogError != nil { return "Games couldn't be loaded. Choose Refresh to try again." }
        if !discoveryFailures.isEmpty { return "Some results couldn't be checked." }
        return nil
    }
    var catalogTitle: String {
        catalogCorpus == "publicMicrosoftStoreSearch" ? "Search results"
            : catalogCorpus == "pcGamePassDiscovery" ? "Explore PC games" : "PC games"
    }
    func catalogMessage(query: String, canRefresh: Bool) -> String {
        if searching { return "Looking for games. Results aren't ready yet." }
        if !isReady { return "Reconnect in Settings to browse games." }
        if !canRefresh { return "This catalog isn't available in this build." }
        if catalogStopped { return "Start a new search when you're ready." }
        if catalogError != nil || !discoveryFailures.isEmpty { return "Try another search or refresh the results." }
        if query.isEmpty { return "Find your next game with Discover or search." }
        return "Try a different title or a shorter search."
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
    var catalogEmptyTitle: String {
        if searching { return "Finding games" }
        if catalogStopped { return "Search stopped" }
        if catalogCorpus == "publicMicrosoftStoreSearch", catalogError == nil,
           discoveryFailures.isEmpty, discoveryCheckedAt != nil { return "No Store matches" }
        return "No games to show"
    }
    func catalogEmptyExplanation(query: String, canRefresh: Bool) -> String {
        if searching { return "Checking public products in this scope. Results are not available yet." }
        if !isReady { return "Connect Xodus in Settings to load public product metadata." }
        if !canRefresh { return "This engine does not provide this catalog operation. Update the paired Xodus build." }
        if catalogStopped { return "Run a new search or refresh this scope when you are ready." }
        if catalogError != nil || !discoveryFailures.isEmpty {
            return "The public catalog could not be fully checked. Refresh to try again; no empty owned library is inferred."
        }
        if query.isEmpty { return "Request public catalog data in this scope. Catalog results do not establish ownership or installation access." }
        if catalogCorpus == "publicMicrosoftStoreSearch", discoveryCheckedAt != nil {
            return "The public Store returned no matching games in this scope. This does not establish availability in other regions or your ownership."
        }
        return "No matching product in this partial catalog. This does not mean the game is unavailable or unowned."
    }

    var currentCredentialState: CredentialState? {
        guard isReady, accountStatusCurrent, !signInPending else { return nil }
        return authentication?.state
    }

    var accountSymbol: String {
        currentCredentialState == .credentialPresent ? "person.crop.circle.fill" : "person.crop.circle"
    }

    var accountLabel: String {
        if phase == .connecting { return "Connecting to Xodus" }
        if phase == .disconnecting { return "Disconnecting from Xodus" }
        guard isReady else { return "Connect Xodus" }
        if signInPending {
            return accountStatusCurrent ? "Sign-in pending" : "Sign-in status needs checking"
        }
        guard accountStatusCurrent else {
            return authentication == nil ? "Account status not checked" : "Account status needs checking"
        }
        switch currentCredentialState {
        case .credentialPresent: return "Microsoft sign-in saved"
        case .expired: return "Sign-in expired"
        case .invalid: return "Sign-in needs attention"
        case .signedOut: return "Sign in with Microsoft"
        case nil: return "Account status not checked"
        }
    }

    var accountExplanation: String {
        guard isReady else {
            return "Connect a trusted development engine in Settings before checking account status. Engine connection is not proof of sign-in."
        }
        if signInPending {
            if !accountStatusCurrent {
                return "The last sign-in result was pending, but its current outcome could not be confirmed. Check status or request cancellation; no completion or cancellation is assumed."
            }
            return "Xodus reports a pending sign-in, not a completed account connection. If Microsoft has opened a sign-in window, continue there yourself or use Cancel sign-in."
        }
        guard accountStatusCurrent else {
            return authentication == nil
                ? "The engine is connected, but account status has not been checked. Status checks don't open Microsoft sign-in or approve Keychain access. Public browsing does not read your Keychain."
                : "Current account status could not be confirmed. Check status before another sign-in or sign-out action; the earlier result is not current account evidence."
        }
        switch currentCredentialState {
        case .credentialPresent:
            return "Saved Microsoft sign-in is not proof of PC ownership, package access or gameplay compatibility."
        case .expired, .invalid:
            return "Disconnect this saved launcher sign-in first, then connect again. Other apps' accounts are not changed."
        case .signedOut:
            return "Xodus reports no saved launcher sign-in. Advertised sign-in support does not verify a paired engine and helper, PC ownership or permission to play."
        case nil:
            return "Account status has not been checked. No saved sign-in or PC access is assumed."
        }
    }

    var accountLibraryTitle: String {
        guard isReady else { return "Connect your Xodus engine" }
        if signInPending { return accountLabel }
        guard accountStatusCurrent else { return accountLabel }
        return currentCredentialState == .credentialPresent
            ? "PC library access is not available yet" : "Your library starts with sign-in"
    }

    var accountLibraryExplanation: String {
        if currentCredentialState == .credentialPresent {
            return "Your Microsoft sign-in is saved, but this engine has not established authoritative PC ownership. No catalog result or play history is shown as an owned game."
        }
        return accountExplanation + " This build cannot yet prove a complete owned-PC library."
    }

    var accountFailureSummary: String? {
        guard let failure = lastSignInFailure else { return nil }
        guard let code = failure.code?.rawValue else {
            return "Stage: stageUnavailable. No successful sign-in or credential commit was assumed."
        }
        if let diagnostic = failure.diagnostic {
            return "Sign-in failure code: \(code). Stage: \(diagnostic.stage). Reason: \(diagnostic.rawValue). "
                + Self.describeConsentFailure(diagnostic)
        }
        return Self.describeSignInFailure(code: code)
    }

    var accountFailureObservation: String? {
        lastSignInFailure?.observation
    }

    nonisolated static func validatedNativeSignInObservation(_ failure: WireFailure) -> String? {
        guard failure.code == "AUTH_INVALID", failure.nativeConsentFailure == .pipelineFailed else { return nil }
        let reasons = ["helper.invalidFrame", "helper.invalidNavigation", "helper.navigationFailed",
                       "helper.popupUnsupported", "helper.contentTerminated", "helper.javaScriptFailed",
                       "helper.bridgeInvalid", "helper.deadlineExpired", "helper.parentUnavailable",
                       "channelEOF", "unclassified", "tokenExchangeFailed", "helperCompletionFailed",
                       "tokenExchange.requestBuild", "tokenExchange.requestSerialization",
                       "tokenExchange.requestTransport", "tokenExchange.requestTimeout",
                       "tokenExchange.httpClientError", "tokenExchange.httpServerError",
                       "tokenExchange.httpStatusRejected", "tokenExchange.responseParsing",
                       "tokenExchange.responseSignature", "tokenExchange.responseCryptography",
                       "tokenExchange.responseEncoding", "tokenExchange.continuationRequired",
                       "tokenExchange.faultWithoutContinuation", "tokenExchange.continuationRejected",
                       "exchangeRetentionFailed"]
        return reasons.map { "Native sign-in failed: \($0)." }.first { $0 == failure.message }
    }

    var accountFailureTitle: String {
        if lastSignInFailure?.diagnostic?.stage == "devicePreparation" {
            return "Microsoft sign-in could not start."
        }
        return "Sign-in did not complete. Try again when you are ready."
    }

    private static func describeSignInFailure(code: String) -> String {
        let reason: String
        switch code {
        case "AUTH_CANCELLED":
            reason = "The sign-in flow was cancelled. No new connection was assumed."
        case "AUTH_EXPIRED":
            reason = "The sign-in flow expired. No completion was assumed."
        case "AUTH_INVALID":
            reason = "The sign-in session could not be validated. The failing step is not identified by this engine."
        case "NETWORK_UNAVAILABLE":
            reason = "The sign-in flow could not reach a required service. No completion was assumed."
        default:
            reason = "No successful sign-in or credential commit was assumed."
        }
        return "Sign-in failure code: \(code). Stage: stageUnavailable. \(reason)"
    }

    private static func describeConsentFailure(_ failure: NativeConsentFailure) -> String {
        switch failure {
        case .bootstrapInvalid:
            "The authentication worker could not initialize safely. Keep the current app and report this diagnostic before another attempt."
        case .clientUnavailable:
            "The native sign-in client could not initialize. Keep the current app and report this diagnostic before another attempt."
        case .credentialStorageUnavailable:
            "Device credentials could not be prepared in Keychain. Personally review its native permission or unlock state before any later attempt."
        case .storedCredentialInvalid:
            "Stored launcher device material could not be validated. No credential deletion or replacement is advised; report this diagnostic."
        case .providerRequestFailed:
            "A provider request during device preparation failed. Its network or service cause is not established; report this diagnostic."
        case .providerProofInvalid:
            "The device-preparation response did not provide a valid sign-in proof. Report this diagnostic before another attempt."
        case .registrationProofInvalid:
            "Microsoft device registration did not provide a valid sign-in proof. Report this diagnostic before another attempt."
        case .tokenResponseInvalid:
            "The device sign-in response did not contain one supported result. Report this diagnostic before another attempt."
        case .tokenProofInvalid:
            "The device sign-in result lacked a valid token proof. Report this diagnostic before another attempt."
        case .tokenStructureInvalid:
            "The device sign-in proof did not have the required supported structure. Report this diagnostic before another attempt."
        case .tokenKindInvalid:
            "The device sign-in token uses a format this launcher cannot accept. Report this diagnostic before another attempt."
        case .tokenAudienceInvalid:
            "The device sign-in token did not match the required context. Report this diagnostic before another attempt."
        case .tokenCipherInvalid:
            "The device sign-in token payload could not be processed. Report this diagnostic before another attempt."
        case .tokenSecretInvalid:
            "The device sign-in proof was missing or invalid. Report this diagnostic before another attempt."
        case .tokenXmlBoundInvalid:
            "The device sign-in payload exceeded the supported processing limit. Report this diagnostic before another attempt."
        case .tokenXmlParseInvalid:
            "The device sign-in payload could not be read in the required format. Report this diagnostic before another attempt."
        case .tokenCipherEncodingInvalid:
            "The device sign-in payload encoding could not be processed. Report this diagnostic before another attempt."
        case .proofUnavailable:
            "Device proof was unavailable. No validated sign-in or package access was established; report this diagnostic."
        case .pipelineFailed:
            "Native sign-in or token exchange failed. This does not establish that a browser appeared or consent completed; report this diagnostic."
        case .proofInvalid:
            "The returned Store proof did not pass validation. No credential commit or package access was established; report this diagnostic."
        case .workerOutcomeUnavailable:
            "Failure stage is unavailable. The worker supplied no usable stage evidence; keep the current app and report the failure code."
        }
    }

    func supports(_ command: ManagementCommand) -> Bool { hello?.supports(command) == true }

#if !XODUS_SHIPPING
    var retiringDisconnectWaiterCount: Int { disconnectWaiters }

    func chooseBackend() {
        guard !connectionTransitioning else {
            errorMessage = "Wait for the current connection transition to finish before choosing another engine."
            return
        }
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
#endif

    func connect() async {
        guard !applicationTerminating else { return }
        guard !connectionTransitioning, !backendPath.isEmpty else {
            if backendPath.isEmpty { errorMessage = "Choose your trusted Xodus build in Settings first." }
            return
        }
        let operationID = UUID()
        connectOperationID = operationID
        lifecycleRevision += 1
        let revision = lifecycleRevision
        updateConnectionTransition()
        defer {
            if connectOperationID == operationID { connectOperationID = nil }
            updateConnectionTransition()
        }
        let state = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Xodus/Management", isDirectory: true)
        guard await retireClient(), revision == lifecycleRevision else { return }
        phase = .connecting
        errorMessage = nil
        let token = generation
        do {
#if XODUS_SHIPPING
            let target = try ShippingPairAdmission.configuration(
                bundle: .main, stateDirectory: state, pins: ShippingPairPins.approved)
            let admittedTarget = target
#else
            let admittedTarget = try configuration ?? BackendConfiguration(
                executable: URL(fileURLWithPath: backendPath), stateDirectory: state,
                nativeAuthHost: NativeAuthHostBinding.bundled(in: .main))
#endif
            let connection = try ManagementClient()
            client = connection
            let negotiated = try await connection.connect(admittedTarget)
            guard token == generation, revision == lifecycleRevision, client === connection else { return }
            hello = negotiated
            let startupQueryRevision = queryGeneration
            phase = .ready
            if supports(.jobs) { try await reconcileActivity() }
            guard token == generation, revision == lifecycleRevision, client === connection else { return }
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
            guard token == generation, revision == lifecycleRevision, client === connection else { return }
            if queryGeneration == startupQueryRevision { await search("") }
        } catch {
            guard token == generation, revision == lifecycleRevision else { return }
            await connectionFailed(error)
        }
    }

    @discardableResult
    func disconnect() async -> Bool {
        lifecycleRevision += 1
        disconnectWaiters += 1
        updateConnectionTransition()
        defer {
            disconnectWaiters -= 1
            updateConnectionTransition()
        }
        return await retireClient()
    }

    private func updateConnectionTransition() {
        connectionTransitioning = connectOperationID != nil || closingOperation != nil || disconnectWaiters > 0
    }

    private func retireClient() async -> Bool {
        if let operation = closingOperation { return await finishRetirement(operation) }
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
        hello = nil
        authentication = nil
        accountStatusCurrent = false
        accountError = nil
        accountStatusError = nil
        failedAccountAction = nil
        activityError = nil
        signInDeadline = nil
        installedSnapshot = nil
        installedSnapshotCurrent = false
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
        diagnosticPreviewing = false
        diagnosticSaved = false
        diagnosticExportError = nil
        phase = .disconnecting
        searching = false
        catalogStopped = false
        lookupBusy = false
        accountBusy = false
        accountStatusChecking = false
        guard let previous = client else {
            phase = .disconnected
            return true
        }
        let shutdown = shutdownClient
        let operation = ClosingOperation(id: UUID(), client: previous,
                                         task: Task { await shutdown(previous) })
        closingOperation = operation
        updateConnectionTransition()
        return await finishRetirement(operation)
    }

    private func finishRetirement(_ operation: ClosingOperation) async -> Bool {
        let closed = await operation.task.value
        if closingOperation?.id == operation.id {
            closingOperation = nil
            if closed {
                client = nil
                phase = .disconnected
            } else {
                // Keep the retiring client owned; no replacement can start without observing its exit.
                phase = .failed
                errorMessage = Self.describe(ManagementError.shutdownFailed)
            }
            updateConnectionTransition()
        }
        return closed
    }

    private func connectionFailed(_ error: Error) async {
        let revision = lifecycleRevision + 1
        guard await disconnect(), revision == lifecycleRevision else { return }
        phase = .failed
        errorMessage = Self.describe(error)
    }

    func refreshAccount() async {
        guard isReady, supports(.authStatus), let client, !accountBusy else { return }
        let token = generation
        authenticationGeneration += 1
        let authToken = authenticationGeneration
        do {
            let status = try await readAccountStatus(using: client, generation: token)
            guard token == generation, authToken == authenticationGeneration else { return }
            acceptAccountStatus(status)
            accountError = nil
            failedAccountAction = nil
            errorMessage = nil
        } catch {
            guard token == generation, authToken == authenticationGeneration else { return }
            accountStatusCurrent = false
            accountStatusError = error as? ManagementError
            accountError = Self.describe(error)
            failedAccountAction = .status
            errorMessage = Self.describe(error)
        }
    }

    private func readAccountStatus(using client: ManagementClient, generation token: Int) async throws -> AuthenticationStatus {
        accountBusy = true
        accountStatusChecking = true
        accountStatusCurrent = false
        defer {
            if token == generation {
                accountBusy = false
                accountStatusChecking = false
            }
        }
        return try await client.request(.authStatus).decode(AuthenticationStatus.self)
    }

    private func acceptAccountStatus(_ status: AuthenticationStatus) {
        if let currentFlow = authentication?.flow, let incomingFlow = status.flow,
           currentFlow.flowID == incomingFlow.flowID,
           currentFlow.state != .pending, incomingFlow.state == .pending { return }
        if let flow = status.flow, flow.state == .failed {
            lastSignInFailure = SignInFailureSnapshot(flow.error)
        } else if status.flow?.state == .completed {
            lastSignInFailure = nil
        }
        authentication = status
        accountStatusCurrent = true
        accountStatusError = nil
    }

    func refreshInstalled() async {
        guard isReady, supports(.installed), let client, !installedRefreshing else { return }
        let token = generation
        installedRefreshing = true
        installedSnapshotCurrent = false
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
            installedSnapshotCurrent = true
        } catch {
            guard token == generation else { return }
            installedError = Self.describe(error)
        }
    }

    func activityTitle(_ job: CatalogJob) -> String {
        products.first { $0.id == job.product.productID }?.title ?? "Game details check"
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
        accountError = nil
        failedAccountAction = nil
        errorMessage = nil
        let token = generation
        do {
            let status = try await client.request(.authBegin, params: ["accountScope": .string("default")])
                .decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard let flow = status.flow else { throw ManagementError.invalidPayload }
            acceptAccountStatus(status)
            signInDeadline = ContinuousClock.now.advanced(by: signInPollingBudget)
            accountBusy = false
            if flow.state == .pending { pollSignIn(flowID: flow.flowID, generation: token) }
        } catch {
            guard token == generation else { return }
            lastSignInFailure = SignInFailureSnapshot(requestError: error)
            accountBusy = false
            accountStatusCurrent = false
            if case let ManagementError.backendError(code, _) = error {
                errorMessage = "Microsoft sign-in could not start. " + Self.describeSignInFailure(code: code)
            } else { errorMessage = Self.describe(error) }
            accountError = errorMessage
            failedAccountAction = .signIn
        }
    }

    private func pollSignIn(flowID: String, generation token: Int) {
        authTask?.cancel()
        authTask = Task { [weak self] in
            let deadline = self?.signInDeadline ?? ContinuousClock.now.advanced(by: self?.signInPollingBudget ?? .seconds(600))
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1))
                    guard let self, token == self.generation, let client = self.client else { return }
                    if self.accountBusy { continue }
                    let finalCheck = ContinuousClock.now >= deadline
                    self.authenticationGeneration += 1
                    let authToken = self.authenticationGeneration
                    let status: AuthenticationStatus
                    do { status = try await self.readAccountStatus(using: client, generation: token) }
                    catch {
                        guard token == self.generation, authToken == self.authenticationGeneration,
                              !Task.isCancelled else { return }
                        self.accountStatusCurrent = false
                        self.accountStatusError = error as? ManagementError
                        self.errorMessage = Self.describe(error)
                        self.accountError = self.errorMessage
                        self.failedAccountAction = .status
                        if error as? ManagementError == .credentialStoreUnavailable { return }
                        if case ManagementError.backendError(_, retryable: true) = error, !finalCheck { continue }
                        return
                    }
                    guard token == self.generation, authToken == self.authenticationGeneration, !Task.isCancelled,
                          self.authentication?.flow?.flowID == flowID,
                          self.authentication?.flow?.state == .pending else { return }
                    guard status.flow?.flowID == flowID else { throw ManagementError.invalidPayload }
                    self.acceptAccountStatus(status)
                    self.accountError = nil
                    self.failedAccountAction = nil
                    if status.flow?.state != .pending {
                        if status.flow?.state == .completed { self.errorMessage = nil }
                        return
                    }
                    if finalCheck || ContinuousClock.now >= deadline {
                        self.accountStatusCurrent = false
                        self.errorMessage = "Sign-in is still pending. Check status before retrying or closing; no cancellation was assumed."
                        self.accountError = self.errorMessage
                        self.failedAccountAction = .status
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, token == self.generation else { return }
                self.errorMessage = Self.describe(error)
                self.accountError = self.errorMessage
                self.failedAccountAction = .status
            }
        }
    }

    func cancelSignIn() async {
        guard let flow = authentication?.flow, flow.state == .pending, let client,
              supports(.authCancel), !accountBusy else { return }
        authenticationGeneration += 1
        accountBusy = true
        accountError = nil
        failedAccountAction = nil
        authTask?.cancel()
        let token = generation
        do {
            let status = try await client.request(.authCancel, params: ["flowID": .string(flow.flowID)])
                .decode(AuthenticationStatus.self)
            guard token == generation else { return }
            guard status.flow?.flowID == flow.flowID, status.flow?.state != .pending else {
                throw ManagementError.invalidPayload
            }
            acceptAccountStatus(status)
            if status.flow?.state == .completed {
                errorMessage = "Sign-in finished before cancellation. Your sign-in is saved; use Sign out to remove it."
            }
        } catch {
            guard token == generation else { return }
            if case ManagementError.backendError("INVALID_TRANSITION", _) = error {
                errorMessage = "Sign-in is finishing. Checking the saved result before closing."
            } else { errorMessage = Self.describe(error) }
            accountError = errorMessage
            failedAccountAction = .cancellation
            if authentication?.flow?.flowID == flow.flowID, signInPending {
                pollSignIn(flowID: flow.flowID, generation: token)
            }
        }
        if token == generation { accountBusy = false }
    }

    func signOut() async {
        guard let client, canDisconnectAccount else {
            errorMessage = "Check the current saved sign-in before disconnecting. No credentials were removed."
            accountError = errorMessage
            failedAccountAction = .signOut
            return
        }
        authenticationGeneration += 1
        accountBusy = true
        accountError = nil
        failedAccountAction = nil
        authTask?.cancel()
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
            accountError = errorMessage
            failedAccountAction = .signOut
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
        activityError = nil
        do {
            _ = try await client.request(command, params: [
                "jobID": .string(job.id), "expectedRevision": .unsigned(job.revision)
            ]).decode(JobResult.self)
            guard token == generation else { return }
            try await reconcileActivity()
        } catch {
            guard token == generation else { return }
            errorMessage = Self.describe(error)
            activityError = Self.describe(error)
        }
    }

    func refreshActivity() async {
        guard isReady, supports(.jobs), !activity.isReconciling else { return }
        let token = generation
        activityError = nil
        do { try await reconcileActivity() }
        catch {
            guard token == generation else { return }
            activityError = Self.describe(error)
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
        guard supports(.diagnostics), let client, !diagnosticSaving, !diagnosticPreviewing else { return }
        diagnosticPreviewing = true
        diagnosticPreview = nil
        diagnosticSaved = false
        diagnosticExportError = nil
        let token = generation
        defer { if token == generation { diagnosticPreviewing = false } }
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

    func chooseDiagnosticDestination() {
        guard diagnosticPreview != nil, !diagnosticSaving, !diagnosticPreviewing else {
            diagnosticExportError = "Preview the current diagnostic summary before saving."
            return
        }
        diagnosticSaved = false
        diagnosticExportError = nil
        let panel = NSSavePanel()
        panel.title = "Save reviewed diagnostic summary"
        panel.nameFieldStringValue = "Xodus-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await saveDiagnosticSummary(to: url) }
    }

    func saveDiagnosticSummary(to destination: URL) async {
        guard let preview = diagnosticPreview, !diagnosticSaving, !diagnosticPreviewing else {
            diagnosticExportError = "Preview the current diagnostic summary before saving."
            return
        }
        diagnosticSaved = false
        diagnosticExportError = nil
        guard destination.isFileURL, destination.host == nil || destination.host == "",
              destination.path.hasPrefix("/"), !destination.hasDirectoryPath else {
            diagnosticExportError = "Choose a local text file for this diagnostic summary."
            return
        }
        diagnosticSaving = true
        defer { diagnosticSaving = false }
        let data = Data(preview.utf8)
        do {
            try await Task.detached(priority: .userInitiated) {
                try data.write(to: destination, options: .atomic)
            }.value
            diagnosticSaved = true
        } catch {
            diagnosticExportError = "The summary could not be saved. Choose a writable destination and try again."
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
