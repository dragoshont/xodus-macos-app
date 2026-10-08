// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
#if !XODUS_SHIPPING
    var allowsStartupTasks = true
#endif

    private var scopedQuery: String { state.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var startupAllowed: Bool {
#if XODUS_SHIPPING
        true
#else
        allowsStartupTasks && !CommandLine.arguments.contains("--export-live") &&
            !PreviewExporter.liveDataRequested && !LibraryPreviewExporter.requested
#endif
    }
    private var searchEnabled: Bool {
        state.destination == .discover
            || (state.destination == .library && !state.showsRecentActivity)
            || (state.showsRecentActivity && session.recentLibrary != nil)
    }
    private var libraryArtworkAllowed: Bool {
#if XODUS_SHIPPING
        startupAllowed
#else
        startupAllowed || LibraryPreviewExporter.requested
#endif
    }
    private var searchPlaceholder: String {
        state.destination == .library ? (state.showsRecentActivity ? "Search recent activity" : "Search your PC games")
            : state.destination == .downloads ? "Search Library or Discover"
            : "Search Discover"
    }
    private var refreshHelp: String {
        if state.destination == .discover {
            return session.discoveryCheckedAt.map { "Refresh Discover - checked \($0)" } ?? "Refresh Discover"
        }
        guard let snapshot = state.pcGames.snapshot else { return "Refresh Library" }
        let age = snapshot.updatedAt.formatted(.relative(presentation: .named))
        return "Refresh Library - updated \(age)"
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GameSetupBannerView(operations: state.gameOperations) {
                    state.showingSetup = !session.signInPending
                    state.showingAccount = true
                }
                if state.destination == .library { library }
                else if state.destination == .discover { catalog }
                else { LiveActivityView(operations: state.gameOperations) }
            }
            .padding(immersiveDestination ? 0 : 30)
        }
        .modifier(LibraryScrollEdge(enabled: immersiveDestination))
        .modifier(LibraryImmersion(enabled: immersiveDestination))
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            XodusToolbar(selection: state.navigationSelection, searchText: $state.query,
                         searchFocused: Binding(get: { searchFocused }, set: { searchFocused = $0 }),
                         searchPlaceholder: searchPlaceholder, searchEnabled: searchEnabled,
                         accountLabel: session.accountLabel,
                         accountSymbol: session.accountSymbol,
                         libraryContrast: immersiveDestination) {
                state.showingAccount = true
            }
            if state.destination == .library && !state.showsRecentActivity {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import installed Xbox game", systemImage: "plus") {
                        Task { await state.installedGames.chooseGame() }
                    }
                    .labelStyle(.iconOnly).help("Import installed game")
                    .modifier(NativeToolbarIconStyle())
                    .disabled(!state.installedGames.loaded || state.installedGames.editing ||
                              state.installedGames.choosing || state.installedGames.mutationActive)
                    .accessibilityIdentifier("xodus.installed.import")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh Library", systemImage: "arrow.clockwise") {
                        if state.pcGames.hasSavedSignIn, !state.pcGames.needsKeychainApproval,
                           !state.pcGames.needsSignIn { state.pcGames.refresh() }
                        Task { await refreshXboxStats() }
                        if state.gameOperations.gamePassActive, session.isReady, session.supports(.discover) {
                            Task { await session.refreshCatalog("") }
                        }
                    }
                        .labelStyle(.iconOnly).help(refreshHelp).keyboardShortcut("r")
                        .modifier(NativeToolbarIconStyle())
                        .disabled(!startupAllowed || state.pcGames.busy)
                        .accessibilityIdentifier("xodus.pcGames.refresh")
                }
            }
            if state.destination == .discover {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh Discover", systemImage: "arrow.clockwise") {
                        Task { await session.refreshCatalog(state.query) }
                    }
                    .labelStyle(.iconOnly).help(refreshHelp).keyboardShortcut("r")
                    .modifier(NativeToolbarIconStyle())
                    .disabled(!startupAllowed || !session.isReady || session.searching)
                    .accessibilityIdentifier("xodus.catalog.refresh")
                }
            }
        }
        .onAppear {
#if !XODUS_SHIPPING
            PreviewExporter.startIfRequested(state: state, session: session)
            LibraryPreviewExporter.start(state: state, session: session)
#endif
        }
#if !XODUS_SHIPPING
        .onReceive(LibraryPreviewExporter.presentation.$showGrid) { show in
            if show { proxy.scrollTo("library-games", anchor: .top) }
        }
#endif
        .task {
            if startupAllowed { await state.runtimeSettings.refreshCrossOverDependency() }
        }
        .task {
            if startupAllowed {
                await state.installedGames.load()
                await state.gameOperations.restore()
                await state.gameOperations.loadGamePassCache()
                state.gameOperations.checkSetupOnce()
            }
        }
        .task(id: scenePhase == .active) {
            if startupAllowed, scenePhase == .active { await refreshXboxStats() }
        }
        .task(id: "\(state.gameOperations.serviceStatus?.accountHash ?? ""):\(state.gameOperations.serviceStatus?.signedIn == true):\(state.gameOperations.serviceSigningIn)") {
            if startupAllowed {
                await LibraryXboxStats.shared.refresh(for: state.gameOperations.serviceStatus,
                    signingIn: state.gameOperations.serviceSigningIn)
            }
        }
        .task {
            if startupAllowed, session.phase == .disconnected, !session.connectionTransitioning,
               !session.backendPath.isEmpty { await session.connect() }
        }
        .task(id: "\(state.destination.rawValue):\(state.showsRecentActivity):\(scenePhase == .active):\(session.isReady):\(session.connectionTransitioning):\(session.accountBusy)") {
            guard startupAllowed, scenePhase == .active else { return }
            await state.loadRecentActivityIfVisible(session: session)
        }
        .task(id: "\(state.destination.rawValue):\(state.query):\(session.market):\(session.language):\(session.isReady)") {
            guard startupAllowed, state.destination == .discover else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await session.refreshCatalog(state.query)
        }
        .sheet(isPresented: $state.showingAccount, onDismiss: { state.showingSetup = false }) {
#if !XODUS_SHIPPING
            LiveAccountView(refreshStatusOnAppear: !PreviewExporter.liveDataRequested)
#else
            LiveAccountView()
#endif
        }
        .sheet(item: $session.selectedProduct) { product in
            LiveProductView(product: product, installed: state.installedGames.games.first { $0.storeId == product.id })
        }
        .background { GameOperationPresentation(operations: state.gameOperations) }
        .background {
            Button("Focus search") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
        }
    }

    private func refreshXboxStats() async {
        guard startupAllowed else { return }
        state.gameOperations.refreshService()
        await state.gameOperations.waitForService()
        await LibraryXboxStats.shared.refresh(for: state.gameOperations.serviceStatus,
            signingIn: state.gameOperations.serviceSigningIn)
    }

    private var immersiveDestination: Bool {
        (state.destination == .library && !state.showsRecentActivity) || state.destination == .discover
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            if state.showsRecentActivity {
                Button("Back to Library", systemImage: "chevron.left") { state.navigate(.library) }
                    .accessibilityIdentifier("xodus.library.back")
                LiveRecentLibraryView(query: scopedQuery,
                                      openAccount: { state.showingAccount = true },
                                      findInStore: { state.findInStore($0, session: session) })
                    .accessibilityIdentifier("xodus.library.recentActivity")
            } else {
                LiveLibraryView(library: state.pcGames, installed: state.installedGames,
                                operations: state.gameOperations, query: scopedQuery,
                                allowsStartupTasks: startupAllowed,
                                allowsArtworkLoading: libraryArtworkAllowed,
                                browse: { state.navigate(.discover) },
                                recentActivity: { state.openRecentActivity() })
            }
            if !state.showsRecentActivity {
                DisclosureGroup("Library details") {
                    VStack(alignment: .leading, spacing: 18) {
                        selectedFolderInspection
                        Divider()
                        Text("Your PC games uses a separate Microsoft sign-in to read this account's game library. It shows active, non-trial games whose Store packages declare PC support.")
                        Text("Installed shows games you've imported or installed with Xodus. It doesn't scan your Mac.")
                        Text("Import an installed Xbox game and choose its working Xodus launch script to play. Removing it from the list keeps its game files and saves.")
                        Text("Inspect a game folder checks its Xodus marker only. This check doesn't import the game or enable Play.")
                    }
                    .padding(.horizontal, 56).padding(.bottom, 28)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                }
            }
        }
    }

    private var selectedFolderInspection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Inspect a game folder") { session.chooseInstallationFolder() }
                    .disabled(!session.isReady || !session.supports(.inspectInstallation) || session.inspectionBusy)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Inspect a game folder")
                    .accessibilityIdentifier("xodus.library.inspectFolder")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { session.chooseInstallationFolder() }
                if session.inspectionBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            Text(session.supports(.inspectInstallation)
                 ? "Choose a folder to check for an existing Xodus marker."
                 : "This build can't inspect a selected game folder.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.inspectionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let inspection = session.inspection {
                LabeledContent("Selected folder",
                               value: URL(fileURLWithPath: inspection.directory).lastPathComponent)
                Text("An external Xodus marker was observed. Retail identity, game-file integrity, access and compatibility remain unknown. No registered entry was created; this game cannot be launched from this result.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Selected folder info") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Container header version", value: inspection.marker.observedPackageVersion)
                        LabeledContent("Marker file",
                                       value: ByteCountFormatter.string(fromByteCount: Int64(inspection.marker.bytes),
                                                                        countStyle: .file))
                        Text("Container ID: \(inspection.marker.contentID)")
                        Text("Header GUID: \(inspection.marker.headerProductGUID)")
                        Text("Header PDUID: \(inspection.marker.headerPDUID)")
                        Text("These header identifiers are not Microsoft Store product, edition or package identities. The metadata digest is not full game integrity.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption).textSelection(.enabled)
                }
            }
        }
    }
    private var catalog: some View {
        LiveCatalogView(library: state.pcGames, installed: state.installedGames,
                        operations: state.gameOperations, query: scopedQuery,
                        allowsArtworkLoading: libraryArtworkAllowed,
                        allowsStartupTasks: startupAllowed, clearSearch: { state.query = "" })
    }
}

struct LiveActivityView: View {
    @ObservedObject var operations: GameOperationsController
    @EnvironmentObject private var session: LiveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Downloads").font(.largeTitle.bold())
                Spacer()
                Button("Refresh activity") {
                    Task { await session.refreshActivity() }
                }.disabled(!session.supports(.jobs) || session.activity.isReconciling)
            }
            GameOperationProgressView(operations: operations)
            if let notice = session.activityNotice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if session.activity.needsSnapshot {
                Label("Refresh activity before changing a check.",
                      systemImage: "arrow.clockwise").foregroundStyle(.secondary)
            }
            if session.activity.jobs.isEmpty {
                if !operations.isBusy && operations.error == nil && operations.notice == nil {
                    ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle",
                        description: Text("Choose Install on a game in your PC Library."))
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else {
                Text("Game details checks").font(.title2.bold())
                Text("These checks don't download games.").foregroundStyle(.secondary)
            }
            ForEach(session.activity.jobs) { job in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: job.state == .completed ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.activityTitle(job)).font(.headline)
                            Text("Game details check").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(job.state.rawValue.capitalized).foregroundStyle(.secondary)
                        if !job.state.isTerminal, session.supports(.cancel) {
                            Button("Cancel check") { Task { await session.changeJob(job, command: .cancel) } }
                                .disabled(session.activity.needsSnapshot || session.activity.isReconciling)
                        }
                        if job.state == .failed, job.error?.retryable == true, job.attempt < 3, session.supports(.retry) {
                            Button("Retry check") { Task { await session.changeJob(job, command: .retry) } }
                                .disabled(session.activity.needsSnapshot || session.activity.isReconciling)
                        }
                    }
                    if let error = job.error {
                        Text(error.retryable && job.attempt < 3 && session.supports(.retry)
                             ? "This check couldn't finish. Choose Retry check to try again."
                             : "This check couldn't finish. Retrying isn't available here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Game info for \(session.activityTitle(job))") {
                        Text("Product \(job.product.productID)").textSelection(.enabled)
                        if let error = job.error { Text("Error: \(error.code)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Divider()
                }
            }
            if let error = session.activityError {
                DisclosureGroup("Error details") { Text(error).foregroundStyle(.secondary) }
            }
        }
    }
}
