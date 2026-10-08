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
            : session.supports(.query) ? "Search your games and Microsoft Store" : "Search your games and checked catalog"
    }
    private var refreshHelp: String {
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
            .padding(state.destination == .library && !state.showsRecentActivity ? 0 : 30)
        }
        .modifier(LibraryScrollEdge(enabled: state.destination == .library && !state.showsRecentActivity))
        .modifier(LibraryImmersion(enabled: state.destination == .library && !state.showsRecentActivity))
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            XodusToolbar(selection: state.navigationSelection, searchText: $state.query,
                         searchFocused: Binding(get: { searchFocused }, set: { searchFocused = $0 }),
                         searchPlaceholder: searchPlaceholder, searchEnabled: searchEnabled,
                         accountLabel: session.accountLabel,
                         accountSymbol: session.accountSymbol,
                         libraryContrast: state.destination == .library && !state.showsRecentActivity) {
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
                        state.pcGames.refresh()
                        if state.gameOperations.gamePassActive, session.isReady, session.supports(.discover) {
                            Task { await session.refreshCatalog("") }
                        }
                    }
                        .labelStyle(.iconOnly).help(refreshHelp).keyboardShortcut("r")
                        .modifier(NativeToolbarIconStyle())
                        .disabled(!startupAllowed || state.pcGames.busy || !state.pcGames.hasSavedSignIn ||
                                  state.pcGames.needsKeychainApproval || state.pcGames.needsSignIn)
                        .accessibilityIdentifier("xodus.pcGames.refresh")
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
                        allowsArtworkLoading: startupAllowed, clearSearch: { state.query = "" })
    }
}

struct LiveCatalogView: View {
    @ObservedObject var library: PCGamesController
    @ObservedObject var installed: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    @EnvironmentObject private var session: LiveSession
    @Environment(\.openSettings) private var openSettings
    let query: String
    var allowsArtworkLoading = true
    let clearSearch: () -> Void

    private var results: CatalogSearchResults {
        CatalogSearchResults(query: query, ownedGames: library.snapshot?.games ?? [],
            storeProducts: session.catalogMatches(query: query) ? session.products : [],
            gamePassProductIDs: session.gamePassProductIDs)
    }

    private var canRefresh: Bool {
        session.isReady && (session.supports(.search)
            || (query.isEmpty ? session.supports(.discover) : session.supports(.query)))
    }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)] }

    var body: some View {
        let results = self.results
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(query.isEmpty ? "Store games" : "Search results").font(.largeTitle.bold())
                    Text(query.isEmpty ? "Find your next PC game."
                         : "Results for \"\(query)\"")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.searching {
                    ProgressView().controlSize(.small)
                    Button("Stop search") { session.stopCatalogSearch() }
                }
                Button("Refresh") { Task { await session.refreshCatalog(query) } }
                    .disabled(session.searching || !canRefresh)
            }
            if !results.ownedMatches.isEmpty {
                Text("Your games").font(.title2.bold())
                if library.error != nil || library.busy {
                    Text("Showing your last complete PC library.").font(.callout).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(results.ownedMatches) { game in
                        PCGameTile(game: game, installed: installed, operations: operations,
                                   allowsArtworkLoading: allowsArtworkLoading, badge: .owned)
                    }
                }
            }
            if !query.isEmpty {
                Text("Microsoft Store").font(.title2.bold())
                if library.snapshot == nil {
                    Text("Load your PC library in Library to include your games in search.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let notice = session.catalogNotice {
                Label(notice, systemImage: session.catalogStopped ? "pause.circle" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if results.storeProducts.isEmpty && results.ownedMatches.isEmpty {
                ContentUnavailableView {
                    Label(session.catalogEmptyTitle,
                          systemImage: "magnifyingglass")
                } description: {
                    Text(session.catalogMessage(query: query, canRefresh: canRefresh))
                } actions: {
                    if !session.isReady { Button("Settings", action: openSettings.callAsFunction) }
                    if !query.isEmpty { Button("Clear search", action: clearSearch) }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if !results.storeProducts.isEmpty {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(results.storeProducts) { product in
                        if let game = results.ownedGame(for: product.id) {
                            PCGameTile(game: game, installed: installed, operations: operations,
                                       allowsArtworkLoading: allowsArtworkLoading, badge: .owned)
                        } else if results.badge(for: product.id) == .gamePass, operations.gamePassActive {
                            PCGameTile(game: PCGame(product: product), installed: installed, operations: operations,
                                       allowsArtworkLoading: allowsArtworkLoading, badge: .gamePass,
                                       viewDetails: { session.selectedProduct = product })
                        } else {
                            storeTile(product, badge: results.badge(for: product.id))
                        }
                    }
                }
            } else if !session.searching && session.catalogError == nil {
                Text("No additional Store matches.").foregroundStyle(.secondary)
            }
            if session.nextCursor != nil, session.catalogMatches(query: query) {
                Button("More games") {
                    Task { await session.refreshCatalog(query, more: true) }
                }
                    .disabled(!session.canLoadMoreCatalog)
                    .accessibilityLabel("Load more catalog results")
                    .accessibilityIdentifier("xodus.catalog.loadMore")
            }
            DisclosureGroup("Catalog info") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Owned comes from your loaded PC library. Game Pass means a game appeared in the loaded PC Game Pass feed, not that your account has access.")
                    Text("Public catalog coverage is partial. Mac compatibility hasn't been checked.")
                    Text("\(session.market) / \(session.language)")
                    if let checked = session.discoveryCheckedAt { Text("Checked \(checked)") }
                    Text(session.catalogCorpus == "publicMicrosoftStoreSearch"
                         ? "Source: Microsoft Store search and public PC metadata."
                         : session.catalogCorpus == "pcGamePassDiscovery"
                            ? "Source: Microsoft's public PC Game Pass feed."
                            : "Source: previously checked public products.")
                    if let error = session.catalogError { Text(error) }
                    ForEach(session.discoveryFailures) { failure in
                        Text("Product \(failure.productID): \(LiveSession.describe(ManagementError.backendError(failure.error.code, retryable: failure.error.retryable)))")
                    }
                }
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .padding(.top, 12)
            }
        }
    }

    private func storeTile(_ product: CatalogProduct, badge: CatalogAccessBadge?) -> some View {
        Button { session.selectedProduct = product } label: {
            VStack(alignment: .leading, spacing: 12) {
                CatalogArtworkView(reference: allowsArtworkLoading ? CatalogArtworkReference.preferred(
                    in: product.artwork, roles: [.boxArt, .poster, .tile, .hero]) : nil,
                    status: product.artworkStatus, contentMode: .fit)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.title).font(.headline).foregroundStyle(.primary)
                        .lineLimit(2).frame(minHeight: 40, alignment: .topLeading)
                    if let badge {
                        Text(badge.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    GameCompatibilityBadge(operations: operations, productID: product.id,
                                           allowsLoading: allowsArtworkLoading)
                    if badge == .gamePass {
                        Text("Included with PC Game Pass").font(.callout).foregroundStyle(.secondary)
                    }
                    if product.freshness == "cached" {
                        Text("Offline details").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.title). \(badge?.rawValue ?? "Access not checked"). \(operations.compatibility[product.id]?.badge ?? "Mac compatibility not checked"). View game.")
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
