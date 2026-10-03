// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
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
            VStack(spacing: 10) {
                FloatingNavigation()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Button { state.showingAccount = true } label: {
                            Image(systemName: session.authentication?.state == .credentialPresent
                                  ? "person.crop.circle.fill" : "person.crop.circle")
                                .font(.title2).frame(width: 48, height: 48).modifier(NativeGlass())
                        }
                        .buttonStyle(.plain).padding(.trailing, 24)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(session.accountLabel)
                        .accessibilityIdentifier("xodus.account")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { state.showingAccount = true }
                    }
                Label(session.isReady ? "Live Xodus connection - development build" : "Xodus for Mac - development build",
                      systemImage: session.isReady ? "cable.connector" : "hammer")
                    .font(.caption).padding(.horizontal, 16).padding(.vertical, 8).modifier(NativeGlass())
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(.container, edges: .top)
            .padding(.top, 16)
        }
        .onAppear {
            PreviewWindow.configure()
            PreviewExporter.startIfRequested(state: state)
        }
        .task {
            if !CommandLine.arguments.contains("--export-live"),
               session.phase == .disconnected, !session.backendPath.isEmpty { await session.connect() }
        }
        .task(id: "\(state.destination.rawValue):\(state.query):\(session.isReady)") {
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
                     : state.destination == .discover ? "Browse public PC Game Pass titles. Keep access and compatibility clear."
                     : session.isReady ? "Catalog checks are live. Game downloads are not enabled in this build."
                     : "Connect Xodus to recover catalog checks. Game downloads are not enabled in this build.")
                    .font(.title3).fixedSize(horizontal: false, vertical: true)
                if state.destination == .library {
                    GlassAction(title: session.accountLabel) { state.showingAccount = true }
                        .controlSize(.large)
                }
                if state.destination != .downloads {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        NativeSearchField(text: $state.query,
                            focused: Binding(get: { searchFocused }, set: { searchFocused = $0 }),
                            placeholder: state.destination == .library ? "Search your Library" : "Search checked catalog",
                            enabled: state.destination == .discover || session.installedSnapshot?.installations.isEmpty == false)
                        if !state.query.isEmpty {
                            Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("Clear catalog search")
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .frame(maxWidth: 640)
                    .modifier(NativeGlass()).environment(\.colorScheme, .dark)
                    .frame(maxWidth: .infinity)
                }
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
                Label(libraryTitle, systemImage: session.isReady ? "square.stack" : "cable.connector")
            } description: {
                Text(libraryExplanation).frame(maxWidth: 520)
            } actions: {
                if !session.isReady {
                    Button("Open Settings", action: openSettings.callAsFunction)
                    if !session.backendPath.isEmpty {
                        Button("Reconnect") { Task { await session.connect() } }
                            .disabled(session.phase == .connecting)
                    }
                } else {
                    Button("Open account") { state.showingAccount = true }
                    Button("Browse checked catalog") { state.navigate(.discover) }
                        .disabled(!session.supports(.search) && !session.supports(.discover))
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
            HStack(alignment: .top, spacing: 28) {
                readiness("Account", session.accountLabel, symbol: "person.crop.circle")
                readiness("PC access", "Not established by catalog or sign-in", symbol: "key")
                readiness("Runtime", "Paired gameplay runtime not certified", symbol: "desktopcomputer")
            }
        }
    }

    private var libraryTitle: String {
        if !session.isReady { return "Connect your Xodus engine" }
        if session.authentication?.state != .credentialPresent { return "Your library starts with sign-in" }
        return "PC library access is not available yet"
    }
    private var libraryExplanation: String {
        if !session.isReady {
            return "Choose a trusted development engine once in Settings. Xodus keeps sign-in in your Mac's Keychain."
        }
        if session.authentication?.state != .credentialPresent {
            return "Use the account control to check or connect Xbox sign-in. This build cannot yet prove a complete owned-PC library."
        }
        return "Your Xbox sign-in is saved, but this engine has not established authoritative PC ownership. No catalog result or play history is shown as an owned game."
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
                Text(state.query.isEmpty && session.supports(.discover) ? "PC Game Pass discovery"
                     : state.query.isEmpty ? "Checked PC catalog" : "Checked catalog search results").font(.title2.bold())
                Spacer()
                if session.searching { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await session.refreshCatalog(state.query) } }
                    .disabled(session.searching || (state.query.isEmpty && session.supports(.discover)
                              ? false : !session.supports(.search)))
            }
            Text("Partial coverage, \(session.market) / \(session.language). These public products are not your owned library.")
                .font(.callout).foregroundStyle(.secondary)
            if session.catalogCorpus == "pcGamePassDiscovery", let checked = session.discoveryCheckedAt {
                Text("Microsoft PC Game Pass public feed - checked \(checked). Search matches products already checked, not the entire Microsoft Store.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    Label(session.searching ? "Checking the catalog" : "No checked products to show",
                          systemImage: "magnifyingglass")
                } description: {
                    Text(!session.isReady ? "Connect Xodus in Settings to load its public product cache."
                         : !session.supports(.search) ? "This engine does not provide catalog search. Update the paired Xodus build."
                         : session.catalogError != nil ? "The public catalog could not be verified. Refresh to try again; no empty owned library is inferred."
                         : state.query.isEmpty && session.supports(.discover) ? "Open Discover to check one public PC Game Pass page. It does not establish ownership or installation access."
                         : state.query.isEmpty ? "This engine lists only products it has checked. Public discovery requires a matching engine update."
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
                if session.nextCursor != nil {
                    Button(session.catalogCorpus == "pcGamePassDiscovery" ? "Browse more PC titles" : "Load more checked products") {
                        Task { await session.refreshCatalog(state.query, more: true) }
                    }
                        .disabled(session.searching)
                }
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
