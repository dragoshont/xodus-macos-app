// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool
#if !XODUS_SHIPPING
    var allowsStartupTasks = true
#endif

    private var scopedQuery: String { state.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var startupAllowed: Bool {
#if XODUS_SHIPPING
        true
#else
        allowsStartupTasks && !CommandLine.arguments.contains("--export-live") && !PreviewExporter.liveDataRequested
#endif
    }
    private var canRefreshCatalog: Bool {
        session.isReady && (session.supports(.search)
            || (scopedQuery.isEmpty ? session.supports(.discover) : session.supports(.query)))
    }
    private var searchEnabled: Bool {
        state.destination == .discover
            || (state.destination == .library && session.recentLibrary != nil)
    }
    private var searchPlaceholder: String {
        state.destination == .library ? "Search recently played"
            : state.destination == .downloads ? "Search Library or Discover"
            : session.supports(.query) ? "Search Microsoft Store games" : "Search checked catalog"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if state.destination == .library { library }
                else if state.destination == .discover { catalog }
                else { LiveActivityView() }
            }
            .padding(30)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            XodusToolbar(selection: state.navigationSelection, searchText: $state.query,
                         searchFocused: Binding(get: { searchFocused }, set: { searchFocused = $0 }),
                         searchPlaceholder: searchPlaceholder, searchEnabled: searchEnabled,
                         accountLabel: session.accountLabel,
                         accountSymbol: session.accountSymbol) { state.showingAccount = true }
        }
        .onAppear {
#if !XODUS_SHIPPING
            PreviewExporter.startIfRequested(state: state, session: session)
#endif
        }
        .task {
            if startupAllowed { await state.runtimeSettings.refreshCrossOverDependency() }
        }
        .task {
            if startupAllowed, session.phase == .disconnected, !session.connectionTransitioning,
               !session.backendPath.isEmpty { await session.connect() }
        }
        .task(id: "\(state.destination.rawValue):\(state.query):\(session.market):\(session.language):\(session.isReady)") {
            guard startupAllowed, state.destination == .discover else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await session.refreshCatalog(state.query)
        }
        .sheet(isPresented: $state.showingAccount) {
#if !XODUS_SHIPPING
            LiveAccountView(refreshStatusOnAppear: !PreviewExporter.liveDataRequested)
#else
            LiveAccountView()
#endif
        }
        .sheet(item: $session.selectedProduct) { product in LiveProductView(product: product) }
        .background {
            Button("Focus search") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            if session.isReady, session.supports(.libraryRecent) {
                LiveRecentLibraryView(query: scopedQuery) { state.showingAccount = true }
            } else {
                ContentUnavailableView {
                    Label(session.isReady ? "Your games" : session.libraryTitle,
                          systemImage: session.isReady ? "gamecontroller" : "cable.connector")
                } description: {
                    Text(session.libraryMessage).frame(maxWidth: 520)
                } actions: {
                    if !session.isReady {
                        Button("Settings", action: openSettings.callAsFunction)
                        if !session.backendPath.isEmpty {
                            Button("Reconnect") { Task { await session.connect() } }
                                .disabled(session.connectionTransitioning)
                        }
                    } else {
                        GlassAction(title: "Browse games") { state.navigate(.discover) }
                            .disabled(!session.supports(.search) && !session.supports(.discover) && !session.supports(.query))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
            DisclosureGroup("Library details") {
                VStack(alignment: .leading, spacing: 18) {
                    selectedFolderInspection
                    Divider()
                    Text(session.accountLibraryExplanation).foregroundStyle(.secondary)
                    Text("Owned-game listing and a durable installed-game registry aren't implemented. The engine's empty registry response isn't a check of your Mac or evidence that no games are installed.")
                    Text("The selected-folder check only reads an Xodus marker. It doesn't scan your Mac, register a game, verify its files, establish ownership, download or enable play.")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scopedQuery.isEmpty ? "Store games" : session.catalogTitle).font(.largeTitle.bold())
                    Text(scopedQuery.isEmpty ? "Find your next PC game."
                         : "Results for \"\(scopedQuery)\"")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.searching {
                    ProgressView().controlSize(.small)
                    Button("Stop search") { session.stopCatalogSearch() }
                }
                Button("Refresh") { Task { await session.refreshCatalog(state.query) } }
                    .disabled(session.searching || !canRefreshCatalog)
            }
            if let notice = session.catalogNotice {
                Label(notice, systemImage: session.catalogStopped ? "pause.circle" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if session.products.isEmpty {
                ContentUnavailableView {
                    Label(session.catalogEmptyTitle,
                          systemImage: "magnifyingglass")
                } description: {
                    Text(session.catalogMessage(query: scopedQuery, canRefresh: canRefreshCatalog))
                } actions: {
                    if !session.isReady { Button("Settings", action: openSettings.callAsFunction) }
                    if !state.query.isEmpty { Button("Clear search") { state.query = "" } }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)], spacing: 28) {
                    ForEach(session.products) { product in
                        Button { session.selectedProduct = product } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                CatalogArtworkView(reference: CatalogArtworkReference.preferred(
                                    in: product.artwork, roles: [.boxArt, .poster, .tile, .hero]),
                                    status: product.artworkStatus)
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(product.title).font(.headline).foregroundStyle(.primary)
                                        .lineLimit(2).frame(minHeight: 40, alignment: .topLeading)
                                    if product.freshness == "cached" {
                                        Text("Offline details").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(product.title). View game. Access not checked.")
                    }
                }
            }
            if session.nextCursor != nil {
                Button("More games") {
                    Task { await session.refreshCatalog(state.query, more: true) }
                }
                    .disabled(!session.canLoadMoreCatalog)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Load more catalog results")
                    .accessibilityIdentifier("xodus.catalog.loadMore")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { Task { await session.refreshCatalog(state.query, more: true) } }
            }
            DisclosureGroup("Catalog info") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Public catalog, not your library. Coverage is partial.")
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
}

struct LiveActivityView: View {
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
            if let notice = session.activityNotice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if session.activity.needsSnapshot {
                Label("Refresh activity before changing a check.",
                      systemImage: "arrow.clockwise").foregroundStyle(.secondary)
            }
            if session.activity.jobs.isEmpty {
                ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle",
                    description: Text("Game downloads aren't available in this build."))
                    .frame(maxWidth: .infinity, minHeight: 240)
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
