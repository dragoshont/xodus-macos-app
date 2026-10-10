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
    var allowsHeroAnimation = true
    let browse: () -> Void
    let recentActivity: () -> Void
    @StateObject private var selection = LibrarySelection()
    @ObservedObject private var art = LibraryCatalogArtwork.shared
    @ObservedObject private var xboxStats = LibraryXboxStats.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        LibraryGame.collection(installed: installed.games, owned: library.representedGames,
                               products: session.products, gamePass: session.gamePassProducts,
                               active: operations.gamePassActive)
    }
    private var visible: [LibraryGame] {
        LibraryGame.visible(filter == .gamePass ? gamePassCatalog : collection,
                            query: query, filter: filter, sort: sort)
    }
    private var gamePassCatalog: [LibraryGame] {
        LibraryGame.gamePassCatalog(installed: installed.games, owned: library.representedGames,
                                    products: session.gamePassProducts)
    }
    private var continuing: [InstalledGame] {
        LibraryGame.continuing(LibraryGame.visible(collection, query: query, filter: filter, sort: sort),
                              launchableIDs: installed.launchableIDs)
    }
    private var localRecords: [LibraryGame] {
        LibraryGame.localRecords(installed: installed.games, qualified: collection, query: query, sort: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if query.isEmpty, let game = continuing.first {
                LibraryHero(title: game.title,
                            logos: (xboxStats.cache?.games[game.storeId]?.logo.map { [$0] } ?? []) +
                                (art.images[game.storeId]?.logos ?? []),
                            allowsArtworkLoading: artworkAllowed) {
                    LibraryHeroMedia(trailer: art.images[game.storeId]?.detail?.trailers.first,
                                     allowsPlayback: allowsStartupTasks && allowsHeroAnimation) {
                        LibraryLandscapeView(references: art.images[game.storeId]?.landscape ?? [],
                                             installed: game, allowsLoading: artworkAllowed)
                    }
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
                    } else if filter == .gamePass {
                        ContentUnavailableView {
                            Label(session.gamePassCatalogLoading || session.gamePassCatalogPaging
                                  ? "Loading PC Game Pass" : "PC Game Pass catalogue unavailable",
                                  systemImage: "ticket")
                        } description: { Text(session.gamePassLibraryNotice) }
                        actions: {
                            Button("Load Game Pass games") {
                                Task { await session.loadGamePassCatalog(refresh: true) }
                            }.disabled(!allowsStartupTasks || !session.isReady || session.gamePassCatalogPaging)
                        }
                    } else if !collection.isEmpty {
                        ContentUnavailableView {
                            Label("No \(filter.rawValue.lowercased()) games", systemImage: "gamecontroller")
                        } description: { Text("Only access-qualified PC games appear in Your Games. Preserved local installations are shown separately below.") }
                        actions: { Button("Show all games") { filter = .all } }
                    } else if library.hasSavedSignIn {
                        ContentUnavailableView {
                            Label("Your games are ready to load", systemImage: "gamecontroller")
                        } description: { Text("Load your account-held PC games. Local installations alone don't confirm account access.") }
                        actions: { Button("Load PC games") { library.refresh() }.disabled(library.busy || library.needsKeychainApproval) }
                    }
                } else {
                    LazyVGrid(columns: LibraryGridLayout.columns,
                              alignment: .leading, spacing: 30) {
                        ForEach(visible) { game in card(game) }
                    }
                }
                if filter == .gamePass {
                    if session.gamePassCatalogLoading || session.gamePassCatalogPaging {
                        ProgressView("Loading PC Game Pass · \(session.gamePassProducts.count.formatted()) games")
                    }
                    Label(session.gamePassLibraryNotice, systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = session.gamePassCatalogError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Refresh Game Pass") {
                            Task { await session.loadGamePassCatalog(refresh: true) }
                        }
                        if session.gamePassCatalogHasMore {
                            Button("Load remaining games") {
                                Task { await session.loadGamePassCatalog() }
                            }
                        }
                    }
                    .disabled(!allowsStartupTasks || !session.isReady || session.gamePassCatalogPaging || session.searching)
                }
                if filter != .gamePass, !localRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Installed on this Mac").font(.title2.weight(.semibold))
                        LazyVGrid(columns: LibraryGridLayout.columns,
                                  alignment: .leading, spacing: 30) {
                            ForEach(localRecords) { game in card(game) }
                        }
                    }.accessibilityIdentifier("xodus.library.localRecords")
                }
                if let error = art.error {
                    Label(error, systemImage: "photo.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                }
                if let error = xboxStats.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                }
            }
            .task(id: (collection.map(\.id) + localRecords.map(\.id) + visible.map(\.id)).sorted().joined(separator: ",")) {
                guard artworkAllowed else { return }
                await art.load(ids: collection.map(\.id) + localRecords.compactMap { $0.installed?.storeId }
                    .filter(PCGamesClient.validProductID) + visible.map(\.id).filter(PCGamesClient.validProductID),
                    market: session.market, language: session.language)
            }
            .padding(.horizontal, 56).padding(.vertical, 22)
        }
        .task { if allowsStartupTasks { await library.loadOnAppear() } }
        .task(id: "\(filter.rawValue):\(session.isReady):\(session.market):\(session.language)") {
            guard allowsStartupTasks, filter == .gamePass else { return }
            await session.loadGamePassCatalog()
        }
        .onChange(of: session.isReady) { _, ready in
            if !ready { selection.requestedGamePassScope = nil }
        }
        .task(id: "\(operations.gamePassActive):\(session.isReady):\(session.searching):\(session.market):\(session.language)") {
            guard allowsStartupTasks, filter != .gamePass, operations.gamePassActive, session.isReady,
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
                        }.frame(width: 260, alignment: .leading).id(game.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection.recentGameID, anchor: .leading)
            .onChange(of: continuing.map(\.id), initial: true) { _, ids in
                if selection.recentGameID.map({ !ids.contains($0) }) ?? true {
                    selection.recentGameID = ids.first
                }
            }
        }
    }

    private func open(_ game: LibraryGame) {
        do {
            let productID = game.installed?.storeId ?? game.id
            guard PCGamesClient.validProductID(productID) else {
                session.errorMessage = "This local record has no verified Store identity. Its files and saves are preserved."
                return
            }
            session.selectedProduct = try game.product ?? art.images[productID]?.product ??
                LibraryGame.details(id: productID, title: game.title, market: session.market, language: session.language,
                                    source: game.owned ? "AccountPCLibrary:identityOnly" : "LocalInstalledRegistry:identityOnly",
                                    pcCandidate: false)
        } catch { session.errorMessage = "Game details couldn't be opened. Your games haven't changed." }
    }

    private func information(id: String, compact: Bool = false) -> some View {
        let metadata = art.images[id]?.facts
        let xbox = xboxStats.cache?.games[id]
        let facts = metadata?.genres.isEmpty == false ? metadata :
            xbox.map { LibraryCatalogFacts(genres: $0.genres, capabilities: metadata?.capabilities ?? []) } ?? metadata
        let game = (filter == .gamePass ? gamePassCatalog : collection).first(where: { $0.id == id })
        return VStack(alignment: .leading, spacing: 5) {
            LibraryGameInformation(access: game.flatMap(LibraryAccess.init),
                                   gamePass: game?.gamePass == true,
                                   facts: facts, xbox: xbox, compact: compact)
        }
    }

    private func card(_ game: LibraryGame) -> some View {
        let artworkID = game.installed?.storeId ?? game.id
        return LibraryCover(title: game.title,
                     openLabel: "View",
                     alwaysShowsActions: game.installed != nil,
                     open: { open(game) }) {
            CatalogArtworkView(reference: artworkAllowed ? art.images[artworkID]?.cover ?? game.cover : nil,
                               status: (art.images[artworkID]?.cover ?? game.cover) == nil ? .absent : .available)
        } status: {
            information(id: game.id, compact: true)
            if game.installed != nil { Label("Installed", systemImage: "internaldrive").font(.caption) }
            LibraryGameSizeView(installed: game.installed, downloadBytes: art.images[artworkID]?.facts.downloadBytes,
                                allowsMeasurement: artworkAllowed)
            if let match = game.installed { InstalledPlayError(library: installed, game: match) }
        } actions: {
            LibraryGlassCluster {
                if let match = game.installed {
                    InstalledPlayButton(library: installed, operations: operations, game: match,
                                        usesGlass: true, prominent: false)
                    InstalledGameActions(library: installed, operations: operations, game: match, usesGlass: true)
                } else if game.owned {
                    Button {
                        if let pc = game.pc { Task { await operations.install(pc) } }
                        else if let product = game.product {
                            Task { await operations.install(PCGame(product: product)) }
                        }
                    } label: {
                        Label("Install", systemImage: "icloud.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .help("Install \(game.title)")
                    .modifier(LibraryActionStyle(primary: false))
                    .disabled(!allowsStartupTasks || !operations.canStartMutation)
                    .accessibilityLabel("Install \(game.title)")
                    .accessibilityIdentifier("xodus.pcGames.download")
                } else if game.gamePass {
                    Button {
                        if let product = game.product {
                            Task { await operations.install(PCGame(product: product)) }
                        }
                    } label: {
                        Label("Install", systemImage: "icloud.and.arrow.down")
                    }
                    .modifier(LibraryActionStyle(primary: false))
                    .disabled(!allowsStartupTasks || !operations.canStartMutation ||
                        !DiscoverBrowse.canReviewInstall(owned: false, accessIsCurrent: false,
                            gamePass: true, subscriptionActive: operations.gamePassActive,
                            pcCandidate: game.product?.pcCatalogCandidate == true))
                    .help("Install \(game.title)")
                    .accessibilityLabel("Install \(game.title)")
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
