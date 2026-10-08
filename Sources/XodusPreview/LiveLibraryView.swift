// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XodusManagement

struct LiveLibraryView: View {
    @ObservedObject var library: PCGamesController
    @ObservedObject var installed: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    @EnvironmentObject private var session: LiveSession
    let query: String
    var allowsStartupTasks = true
    var allowsArtworkLoading: Bool? = nil
    let browse: () -> Void
    let recentActivity: () -> Void
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var art = LibraryCatalogArtwork.shared
    @ObservedObject private var xboxStats = LibraryXboxStats.shared
    private var artworkAllowed: Bool { allowsArtworkLoading ?? allowsStartupTasks }
    private var filter: LibraryFilter {
        get { selection.filter }
        nonmutating set { selection.filter = newValue }
    }
    private var sort: LibrarySort {
        get { selection.sort }
        nonmutating set { selection.sort = newValue }
    }

    private var collection: [LibraryGame] {
        LibraryGame.collection(installed: installed.games, owned: library.snapshot?.games ?? [],
                               products: session.products, gamePass: session.gamePassProducts,
                               active: operations.gamePassActive)
    }
    private var visible: [LibraryGame] {
        LibraryGame.visible(collection, query: query, filter: filter, sort: sort)
    }
    private var continuing: [InstalledGame] {
        installed.games.filter { $0.lastPlayedAt != nil && installed.launchableIDs.contains($0.id) }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if query.isEmpty, let game = installed.continuingGame {
                LibraryHero(title: game.title,
                            logos: (xboxStats.cache?.games[game.storeId]?.logo.map { [$0] } ?? []) +
                                (art.images[game.storeId]?.logos ?? []),
                            allowsArtworkLoading: artworkAllowed) {
                    LibraryLandscapeView(references: art.images[game.storeId]?.landscape ?? [],
                                         installed: game, allowsLoading: artworkAllowed)
                } poster: {
                    LibraryLandscapeView(references: art.images[game.storeId]?.cover.map { [$0] } ?? [],
                                         installed: game, allowsLoading: artworkAllowed)
                } information: {
                    information(id: game.storeId)
                    LibraryGameSizeView(installed: game, downloadBytes: nil, allowsMeasurement: artworkAllowed)
                } actions: {
                    InstalledPlayButton(library: installed, operations: operations, game: game,
                                        usesGlass: true, heroStyle: true)
                    InstalledGameActions(library: installed, operations: operations, game: game,
                                         usesGlass: true, heroStyle: true)
                }
                InstalledPlayError(library: installed, game: game).padding(.horizontal, 56)
            }
            VStack(alignment: .leading, spacing: 22) {
                if query.isEmpty, !continuing.isEmpty { continuePlaying }
                GameOperationProgressView(operations: operations)
                if let error = installed.error {
                    ContentUnavailableView {
                        Label("Installed games unavailable", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Try again") { Task { await installed.load() } }.disabled(installed.loading)
                    }
                }
                if let error = installed.historyError {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
                PCGamesView(library: library, installed: installed, operations: operations,
                            query: query, allowsStartupTasks: allowsStartupTasks, showsCollection: false,
                            browse: browse, recentActivity: recentActivity)
                LibraryControls(count: visible.count, filter: $selection.filter, sort: $selection.sort)
                    .id("library-games")
                if installed.loading { ProgressView("Loading installed games") }
                if visible.isEmpty {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else if filter == .gamePass, operations.gamePassActive, session.gamePassProducts.isEmpty {
                        ContentUnavailableView {
                            Label("Game Pass catalog not loaded", systemImage: "ticket")
                        } description: { Text("Your saved subscription status doesn't supply a game list. Refresh Library when Xodus is connected.") }
                    } else if !collection.isEmpty {
                        ContentUnavailableView {
                            Label("No \(filter.rawValue.lowercased()) games", systemImage: "gamecontroller")
                        } description: { Text("Games appear here when their access or installation is known.") }
                        actions: { Button("Show all games") { filter = .all } }
                    } else if library.hasSavedSignIn {
                        ContentUnavailableView {
                            Label("Your games are ready to load", systemImage: "gamecontroller")
                        } description: { Text("Load your PC library, or import a game already installed with Xodus.") }
                        actions: { Button("Load PC games") { library.refresh() }.disabled(library.busy || library.needsKeychainApproval) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 24)],
                              alignment: .leading, spacing: 30) {
                        ForEach(visible) { game in card(game) }
                    }
                }
                if session.catalogCorpus == "pcGamePassDiscovery", operations.gamePassActive,
                   let notice = session.catalogNotice {
                    Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                if let error = art.error {
                    Label(error, systemImage: "photo.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                }
                if let error = xboxStats.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                }
            }
            .task(id: collection.map(\.id).sorted().joined(separator: ",")) {
                guard artworkAllowed else { return }
                await art.load(ids: collection.map(\.id), market: session.market, language: session.language)
            }
            .padding(.horizontal, 56).padding(.vertical, 22)
        }
        .task { if allowsStartupTasks { await library.loadOnAppear() } }
        .onChange(of: session.isReady) { _, ready in
            if !ready { selection.requestedGamePassScope = nil }
        }
        .task(id: "\(operations.gamePassActive):\(session.isReady):\(session.searching):\(session.market):\(session.language)") {
            guard allowsStartupTasks, operations.gamePassActive, session.isReady,
                  session.supports(.discover), session.gamePassProducts.isEmpty, !session.searching else { return }
            let scope = "\(session.market):\(session.language)"
            guard selection.requestedGamePassScope != scope else { return }
            selection.requestedGamePassScope = scope
            await session.refreshCatalog("")
        }
    }

    private var continuePlaying: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Continue Playing").font(.title2.weight(.semibold))
                Spacer()
                Button("See All") { filter = .installed; sort = .recentlyPlayed }
                    .accessibilityLabel("Show installed games by last played")
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(continuing) { game in
                        VStack(alignment: .leading, spacing: 10) {
                            LibraryLandscapeView(references: art.images[game.storeId]?.landscape ?? [],
                                                 installed: game, allowsLoading: artworkAllowed)
                                .frame(width: 260, height: 110).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) {
                                    InstalledPlayButton(library: installed, operations: operations, game: game,
                                                        usesGlass: true, prominent: false)
                                        .padding(12)
                                }
                            Text(game.title).font(.headline).lineLimit(1)
                            information(id: game.storeId, compact: true)
                            LibraryGameSizeView(installed: game, downloadBytes: nil, allowsMeasurement: artworkAllowed)
                            if let date = game.lastPlayedAt {
                                Text("Last played \(Text(date, style: .relative)) ago")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            InstalledPlayError(library: installed, game: game)
                        }.frame(width: 260, alignment: .leading)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
        }
    }

    private func open(_ game: LibraryGame) {
        do {
            session.selectedProduct = try game.product ?? art.images[game.id]?.product ??
                LibraryGame.details(id: game.id, title: game.title, market: session.market, language: session.language,
                                    source: game.owned ? "AccountPCLibrary:identityOnly" : "LocalInstalledRegistry:identityOnly",
                                    pcCandidate: false)
        } catch { session.errorMessage = "Game details couldn't be opened. Your games haven't changed." }
    }

    private func information(id: String, compact: Bool = false) -> some View {
        let metadata = art.images[id]?.facts
        let xbox = xboxStats.cache?.games[id]
        let facts = metadata?.genres.isEmpty == false ? metadata :
            xbox.map { LibraryCatalogFacts(genres: $0.genres, capabilities: metadata?.capabilities ?? []) } ?? metadata
        return LibraryGameInformation(access: collection.first(where: { $0.id == id }).flatMap(LibraryAccess.init),
                                      facts: facts, xbox: xbox, compact: compact)
    }

    private func card(_ game: LibraryGame) -> some View {
        LibraryCover(title: game.title,
                     openLabel: "View",
                     open: { open(game) }) {
            CatalogArtworkView(reference: artworkAllowed ? art.images[game.id]?.cover ?? game.cover : nil,
                               status: (art.images[game.id]?.cover ?? game.cover) == nil ? .absent : .available)
        } status: {
            information(id: game.id, compact: true)
            if game.installed != nil { Label("Installed", systemImage: "internaldrive").font(.caption) }
            LibraryGameSizeView(installed: game.installed, downloadBytes: art.images[game.id]?.facts.downloadBytes,
                                allowsMeasurement: artworkAllowed)
            GameCompatibilityBadge(operations: operations, productID: game.id, allowsLoading: allowsStartupTasks)
            if let match = game.installed { InstalledPlayError(library: installed, game: match) }
        } actions: {
            LibraryGlassCluster {
                if let match = game.installed {
                    InstalledPlayButton(library: installed, operations: operations, game: match,
                                        usesGlass: true, prominent: false)
                    InstalledGameActions(library: installed, operations: operations, game: match, usesGlass: true)
                } else {
                    Button(game.actionTitle) {
                        if let pc = game.pc { Task { await operations.prepareInstall(pc) } }
                        else if let product = game.product {
                            Task { await operations.prepareInstall(PCGame(product: product)) }
                        }
                    }.modifier(LibraryActionStyle(primary: false))
                    .disabled(!operations.canStartMutation).accessibilityLabel("Install \(game.title)")
                    .accessibilityIdentifier("xodus.pcGames.install")
                }
            }
        }
        .contextMenu {
            if let match = game.installed {
                InstalledGameManagement(library: installed, operations: operations, game: match)
                Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: match.folder) }
            } else { Button("View game") { open(game) } }
        }
    }
}
