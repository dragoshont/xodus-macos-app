// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct PCGamesView: View {
    @ObservedObject var library: PCGamesController
    @ObservedObject var installed: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    let query: String
    var allowsStartupTasks = true
    let browse: () -> Void
    let recentActivity: () -> Void

    private var visibleGames: [PCGame] {
        (library.snapshot?.games ?? []).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !library.hasSavedSignIn || library.needsSignIn {
                ContentUnavailableView {
                    Label("Sign in to see your PC games", systemImage: "gamecontroller")
                } description: {
                    Text("See the games in your Microsoft account that are available for PC.")
                        .frame(maxWidth: 520)
                } actions: {
                    Button("Sign in") { library.signIn() }
                        .buttonStyle(.borderedProminent).disabled(library.busy)
                        .accessibilityIdentifier("xodus.pcGames.signIn")
                    Button("Browse games", action: browse)
                    Button("Recent activity", action: recentActivity)
                        .accessibilityIdentifier("xodus.library.openRecentActivity")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Your PC games").font(.title.bold())
                    if let snapshot = library.snapshot {
                        Text("\(snapshot.games.count)").font(.title3).foregroundStyle(.secondary)
                            .accessibilityLabel("\(snapshot.games.count) PC games")
                    }
                    Spacer()
                    Button(library.snapshot == nil ? "Load PC games" : "Refresh") { library.refresh() }
                        .disabled(library.busy).accessibilityIdentifier("xodus.pcGames.refresh")
                    Button("Sign out of PC games") { Task { await library.signOut() } }
                        .disabled(library.busy).accessibilityIdentifier("xodus.pcGames.signOut")
                }
                if library.busy {
                    ProgressView("Loading your PC games").controlSize(.small)
                        .accessibilityIdentifier("xodus.pcGames.loading")
                }
                if let snapshot = library.snapshot {
                    if snapshot.games.isEmpty {
                        Text("No PC games were found in this account.").foregroundStyle(.secondary)
                    } else if visibleGames.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)], spacing: 28) {
                            ForEach(visibleGames) { game in
                                PCGameTile(game: game, installed: installed, operations: operations,
                                           allowsArtworkLoading: allowsStartupTasks, badge: query.isEmpty ? nil : .owned)
                            }

                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if snapshot.excludedCount > 0 {
                            Text("\(snapshot.excludedCount) games not shown (not for PC or unavailable)")
                        }
                        Text("Last updated \(Text(snapshot.updatedAt, style: .relative)) ago")
                        if library.error != nil { Text("Showing the last complete library.") }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                } else if !library.busy {
                    Text("Load your library to see your PC games.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Browse games", action: browse)
                    Button("Recent activity", action: recentActivity)
                        .accessibilityIdentifier("xodus.library.openRecentActivity")
                }
            }
            if let error = library.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.pcGames.error")
            }
        }
        .task { if allowsStartupTasks { await library.restorePresence() } }
        .sheet(isPresented: Binding(get: { library.sheetPresented }, set: { value in
            if !value { Task { await library.cancelSignIn() } }
        })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sign in to see your PC games").font(.title2.bold())
                Text("Open Microsoft's sign-in page and enter this code to see the PC games in your account.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let code = library.deviceCode {
                    Text(code.userCode).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
                        .accessibilityLabel("Microsoft sign-in code, \(code.userCode)")
                        .accessibilityIdentifier("xodus.pcGames.deviceCode")
                    Button("Open microsoft.com/link") { library.openVerification() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("xodus.pcGames.openVerification")
                    Text("Waiting for you to finish sign-in.").foregroundStyle(.secondary)
                } else if library.busy { ProgressView("Preparing sign-in").controlSize(.small) }
                if let error = library.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { Task { await library.cancelSignIn() } }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("xodus.pcGames.cancel")
                }
            }
            .padding(28).frame(width: 480)
            .interactiveDismissDisabled(library.busy)
        }
    }
}

struct PCGameTile: View {
    let game: PCGame
    @ObservedObject var installed: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    var allowsArtworkLoading = true
    var badge: CatalogAccessBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatalogArtworkView(reference: allowsArtworkLoading ? game.artwork : nil,
                               status: game.artwork == nil ? .absent : .available, contentMode: .fit)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(game.title).font(.headline)
                .lineLimit(2).frame(minHeight: 40, alignment: .topLeading)
            if let badge {
                Text(badge.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            GameCompatibilityBadge(operations: operations, productID: game.id, allowsLoading: allowsArtworkLoading)
            if let match = PCGamesController.installedMatch(game, in: installed.games) {
                InstalledPlayButton(library: installed, game: match)
                InstalledPlayError(library: installed, game: match)
            } else {
                Text("Not installed").font(.callout).foregroundStyle(.secondary)
                Button("Install") { Task { await operations.prepareInstall(game) } }
                    .disabled(!operations.canStartMutation)
                    .accessibilityLabel("Install \(game.title)")
                    .accessibilityIdentifier("xodus.pcGames.install")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
