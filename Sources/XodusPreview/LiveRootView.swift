// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

    private var scopedQuery: String { state.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRefreshCatalog: Bool {
        session.isReady && (session.supports(.search)
            || (scopedQuery.isEmpty ? session.supports(.discover) : session.supports(.query)))
    }
    private var searchEnabled: Bool {
        state.destination == .discover || (state.destination == .library
            && session.installedSnapshot?.installations.isEmpty == false)
    }
    private var searchPlaceholder: String {
        state.destination == .library ? "Search your Library"
            : state.destination == .downloads ? "Search Library or Discover"
            : session.supports(.query) ? "Search Microsoft Store games" : "Search checked catalog"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    if state.destination == .library { library }
                    else if state.destination == .discover { catalog }
                    else { LiveActivityView() }
                }
                .padding(30)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            XodusToolbar(selection: state.navigationSelection, searchText: $state.query,
                         searchFocused: Binding(get: { searchFocused }, set: { searchFocused = $0 }),
                         searchPlaceholder: searchPlaceholder, searchEnabled: searchEnabled,
                         accountLabel: session.accountLabel,
                         accountSymbol: session.accountSymbol) { state.showingAccount = true }
        }
        .onAppear {
            PreviewExporter.startIfRequested(state: state)
        }
        .task {
            if !CommandLine.arguments.contains("--export-live"),
               session.phase == .disconnected, !session.connectionTransitioning,
               !session.backendPath.isEmpty { await session.connect() }
        }
        .task(id: "\(state.destination.rawValue):\(state.query):\(session.market):\(session.language):\(session.isReady)") {
            guard state.destination == .discover else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await session.refreshCatalog(state.query)
        }
        .sheet(isPresented: $state.showingAccount) { LiveAccountView() }
        .sheet(item: $session.selectedProduct) { product in LiveProductView(product: product) }
        .background {
            Button("Focus search") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(kind: state.destination == .downloads ? "orbit" : "harbor")
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                Text(state.destination == .library ? "A place for your next adventure."
                     : state.destination == .discover ? "Find your next world." : "Keep an eye on every step.")
                    .font(.system(size: 42, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
                Text(state.destination == .library ? "Start with your account. Keep access and compatibility clear."
                     : state.destination == .discover ? (scopedQuery.isEmpty
                         ? "Browse public PC Game Pass titles. Keep access and compatibility clear."
                         : session.supports(.query) ? "Search Microsoft Store games. Keep access and compatibility clear."
                         : "Search checked public products. Keep access and compatibility clear.")
                     : session.isReady ? "Catalog checks are live. Game downloads are not enabled in this build."
                     : "Connect Xodus to recover catalog checks. Game downloads are not enabled in this build.")
                    .font(.title3).fixedSize(horizontal: false, vertical: true)
                if state.destination == .library {
                    GlassAction(title: session.accountLabel) { state.showingAccount = true }
                        .controlSize(.large)
                }
                Label(session.isReady ? "Connected development engine" : "Development build - engine not connected",
                      systemImage: session.isReady ? "cable.connector" : "hammer")
                    .font(.caption)
                Text("Original landscape illustration - not a game screenshot.")
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
            }
            .foregroundStyle(.white).padding(30)
        }
        .frame(height: state.destination == .downloads ? 330 : 430)
        .clipped()
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your Library").font(.title2.bold())
                Spacer()
                if session.phase == .connecting { ProgressView().controlSize(.small) }
                Button("Account") { state.showingAccount = true }
            }
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ContentUnavailableView {
                Label(session.accountLibraryTitle, systemImage: session.isReady ? "square.stack" : "cable.connector")
            } description: {
                Text(session.accountLibraryExplanation).frame(maxWidth: 520)
            } actions: {
                if !session.isReady {
                    Button("Open Settings", action: openSettings.callAsFunction)
                    if !session.backendPath.isEmpty {
                        Button("Reconnect") { Task { await session.connect() } }
                            .disabled(session.connectionTransitioning)
                    }
                } else {
                    Button("Open account") { state.showingAccount = true }
                    Button("Browse checked catalog") { state.navigate(.discover) }
                        .disabled(!session.supports(.search) && !session.supports(.discover) && !session.supports(.query))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            if session.isReady && session.supports(.installed) {
                Divider()
                HStack {
                    Text("Registered on this Mac").font(.title2.bold())
                    Spacer()
                    if session.installedRefreshing { ProgressView().controlSize(.small) }
                    Button("Check installed status") { Task { await session.refreshInstalled() } }
                        .disabled(session.installedRefreshing)
                }
                Text("Xodus management registry only. Other game folders have not been scanned. Registration does not establish current access or permission to play.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = session.installedError {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
                if let snapshot = session.installedSnapshot {
                    let matches = snapshot.installations.filter {
                        state.query.isEmpty || session.installationTitle($0).localizedCaseInsensitiveContains(state.query)
                            || $0.productID.localizedCaseInsensitiveContains(state.query)
                    }
                    if snapshot.installations.isEmpty {
                        Text("No installations in this managed registry. Existing games outside it have not been checked.")
                            .foregroundStyle(.secondary)
                    } else if matches.isEmpty {
                        Text("No registered installation matches this Library search.").foregroundStyle(.secondary)
                    }
                    ForEach(matches) { installation in
                        HStack(spacing: 16) {
                            Image(systemName: "gamecontroller").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.installationTitle(installation)).font(.headline)
                                Text("Package \(installation.packageVersion) - \(installation.health.label)")
                                    .font(.callout).foregroundStyle(.secondary)
                                Text("Access and current file integrity must be checked before launch.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Installed status has not been verified.").foregroundStyle(.secondary)
                }
            }
            Divider()
            selectedFolderInspection
            Divider()
            HStack(alignment: .top, spacing: 28) {
                readiness("Account", session.accountLabel, symbol: "person.crop.circle")
                readiness("PC access", "Not established by catalog or sign-in", symbol: "key")
                readiness("Runtime", "Paired gameplay runtime not certified", symbol: "desktopcomputer")
            }
        }
    }

    private var selectedFolderInspection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("A game folder you choose").font(.title2.bold())
                Spacer()
                if session.inspectionBusy { ProgressView().controlSize(.small) }
                Button("Inspect a game folder") { session.chooseInstallationFolder() }
                    .disabled(!session.isReady || !session.supports(.inspectInstallation) || session.inspectionBusy)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Inspect a game folder")
                    .accessibilityIdentifier("xodus.library.inspectFolder")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { session.chooseInstallationFolder() }
            }
            Text(session.supports(.inspectInstallation)
                 ? "Read-only marker check in one selected folder. No scan, registration, download or launch."
                 : "Read-only selected-folder inspection requires a matching engine capability. No other game folders have been scanned.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.inspectionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let inspection = session.inspection {
                LabeledContent("Selected folder",
                               value: URL(fileURLWithPath: inspection.directory).lastPathComponent)
                LabeledContent("Container header version", value: inspection.marker.observedPackageVersion)
                LabeledContent("Marker file",
                               value: ByteCountFormatter.string(fromByteCount: Int64(inspection.marker.bytes),
                                                                countStyle: .file))
                Text("An external Xodus marker was observed. Retail identity, game-file integrity, access and compatibility remain unknown. No registered entry was created; this game cannot be launched from this result.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Observed metadata") {
                    VStack(alignment: .leading, spacing: 8) {
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
    private func readiness(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(scopedQuery.isEmpty && session.supports(.discover) ? "PC Game Pass discovery"
                     : scopedQuery.isEmpty ? "Checked PC catalog"
                     : session.supports(.query) ? "Microsoft Store search results" : "Checked catalog search results")
                    .font(.title2.bold())
                Spacer()
                if session.searching {
                    ProgressView().controlSize(.small)
                    Button("Stop search") { session.stopCatalogSearch() }
                }
                Button("Refresh") { Task { await session.refreshCatalog(state.query) } }
                    .disabled(session.searching || !canRefreshCatalog)
            }
            Text("Partial coverage, \(session.market) / \(session.language). These public products are not your owned library.")
                .font(.callout).foregroundStyle(.secondary)
            if session.catalogCorpus == "pcGamePassDiscovery", let checked = session.discoveryCheckedAt {
                Text("Microsoft PC Game Pass public feed - checked \(checked). Public catalog, not ownership proof.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if session.catalogCorpus == "publicMicrosoftStoreSearch", let checked = session.discoveryCheckedAt {
                Text("Microsoft Store public search - checked \(checked). PC candidates are independently checked against public product metadata; coverage remains partial.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !scopedQuery.isEmpty && !session.supports(.query) {
                Text("This engine searches only products already checked, not the whole Microsoft Store. Update the paired engine for network search.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if session.catalogStopped {
                Label("Search stopped. Refresh when you are ready; no later result from that request will be shown.",
                      systemImage: "pause.circle").foregroundStyle(.secondary)
            }
            if let error = session.catalogError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
            ForEach(session.discoveryFailures) { failure in
                Label("Product \(failure.productID) could not be checked. \(LiveSession.describe(ManagementError.backendError(failure.error.code, retryable: failure.error.retryable)))",
                      systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if session.products.isEmpty {
                ContentUnavailableView {
                    Label(session.searching ? "Checking the catalog" : session.catalogStopped ? "Search stopped"
                          : session.catalogCorpus == "publicMicrosoftStoreSearch" && session.catalogError == nil
                            && session.discoveryFailures.isEmpty ? "No Store matches" : "No checked products to show",
                          systemImage: "magnifyingglass")
                } description: {
                    Text(!session.isReady ? "Connect Xodus in Settings to load its public product cache."
                         : !canRefreshCatalog ? "This engine does not provide this catalog operation. Update the paired Xodus build."
                         : session.catalogStopped ? "Run a new search or refresh this scope when you are ready."
                         : session.catalogError != nil ? "The public catalog could not be verified. Refresh to try again; no empty owned library is inferred."
                         : scopedQuery.isEmpty && session.supports(.discover) ? "Open Discover to check one public PC Game Pass page. It does not establish ownership or installation access."
                         : scopedQuery.isEmpty ? "This engine lists only products it has checked. Public discovery requires a matching engine update."
                         : session.catalogCorpus == "publicMicrosoftStoreSearch" ? "The public Store returned no matching games in this scope. This does not establish availability in other regions or your ownership."
                         : "No matching product in this partial catalog. This does not mean the game is unavailable or unowned.")
                } actions: {
                    Button("Open Settings", action: openSettings.callAsFunction)
                    if !state.query.isEmpty { Button("Clear search") { state.query = "" } }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 24)], spacing: 26) {
                    ForEach(session.products) { product in
                        Button { session.selectedProduct = product } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "gamecontroller")
                                    .font(.title2).foregroundStyle(.secondary)
                                    .frame(width: 64, height: 64)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(product.title).font(.headline).foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Access unverified").font(.callout).foregroundStyle(.secondary)
                                    Text(product.freshness == "cached" ? "Cached public metadata" : "Public metadata")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("View editions").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(product.title), public catalog. Access unverified. View editions.")
                    }
                }
            }
            if session.nextCursor != nil {
                Button(session.catalogCorpus == "pcGamePassDiscovery" ? "Browse more PC titles"
                       : session.catalogCorpus == "publicMicrosoftStoreSearch" ? "Search more Store games"
                       : "Load more checked products") {
                    Task { await session.refreshCatalog(state.query, more: true) }
                }
                    .disabled(!session.canLoadMoreCatalog)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Load more catalog results")
                    .accessibilityIdentifier("xodus.catalog.loadMore")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { Task { await session.refreshCatalog(state.query, more: true) } }
            }
        }
    }
}

struct LiveActivityView: View {
    @EnvironmentObject private var session: LiveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Activity").font(.title2.bold())
                Spacer()
                Button("Refresh activity") {
                    Task {
                        do { try await session.reconcileActivity() }
                        catch { session.errorMessage = LiveSession.describe(error) }
                    }
                }.disabled(!session.supports(.jobs) || session.activity.isReconciling)
            }
            Text("Durable catalog checks only. No game packages are being downloaded or installed.")
                .foregroundStyle(.secondary)
            if session.activity.needsSnapshot {
                Label("Activity is not current. Reconnect or refresh before cancelling or retrying a check.",
                      systemImage: "arrow.clockwise").foregroundStyle(.secondary)
            }
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
            if session.activity.jobs.isEmpty {
                ContentUnavailableView("No catalog checks", systemImage: "arrow.down.circle",
                    description: Text("Public product checks appear here with real cancellation and recovery. Game-download support is still in development."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
            ForEach(session.activity.jobs) { job in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: job.state == .completed ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Catalog check").font(.headline)
                            Text(job.product.productID).font(.callout).textSelection(.enabled)
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
                        Text("Xodus reported \(error.code).").font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
    }
}
