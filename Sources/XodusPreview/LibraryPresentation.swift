// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", installed = "Installed", owned = "Owned", gamePass = "Game Pass"
    var id: Self { self }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title", recentlyPlayed = "Recently played"
    var id: Self { self }
}

@MainActor
final class LibrarySelection: ObservableObject {
    @Published var filter: LibraryFilter = .all
    @Published var sort: LibrarySort = .title
    var requestedGamePassScope: String?
}

@MainActor
final class LibraryCoverInteraction: ObservableObject {
    @Published var hovered = false
}

struct LibraryGame: Identifiable {
    let id: String
    let title: String
    let installed: InstalledGame?
    let pc: PCGame?
    let product: CatalogProduct?
    let owned: Bool
    let gamePass: Bool
    var actionTitle: String {
        installed != nil ? "Play" : owned ? "Download" : "Install"
    }

    var cover: CatalogArtworkReference? {
        if let art = pc?.artwork, [.boxArt, .poster].contains(art.role),
           let width = art.width, let height = art.height, height > width { return art }
        return product.flatMap {
            CatalogArtworkReference.preferred(in: $0.artwork.filter {
                guard let width = $0.width, let height = $0.height else { return false }
                return height > width
            }, roles: [.boxArt, .poster])
        }
    }

    static func details(id: String, title: String, artwork: [CatalogArtworkReference] = [],
                        market: String, language: String, source: String, pcCandidate: Bool) throws -> CatalogProduct {
        let art = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(artwork))
        let value = JSONValue.object([
            "productID": .string(id), "title": .string(title), "market": .string(market),
            "language": .string(language), "source": .string(source),
            "checkedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "freshness": .string("current"), "editions": .array([]),
            "pcCatalogCandidate": .bool(pcCandidate), "artwork": art,
            "artworkStatus": .string(artwork.isEmpty ? "absent" : "available")
        ])
        return try JSONDecoder().decode(CatalogProduct.self, from: JSONEncoder().encode(value))
    }

    static func collection(installed: [InstalledGame], owned: [PCGame], products: [CatalogProduct],
                           gamePass: [CatalogProduct], active: Bool) -> [Self] {
        var result: [Self] = []
        var seen = Set<String>()
        let catalog = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pass = Dictionary(gamePass.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let purchases = Dictionary(owned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for game in installed {
            let id = game.storeId.isEmpty ? game.id.uuidString : game.storeId
            guard seen.insert(id).inserted else { continue }
            result.append(Self(id: id, title: game.title, installed: game, pc: purchases[id],
                               product: catalog[id] ?? pass[id], owned: purchases[id] != nil,
                               gamePass: active && pass[id] != nil))
        }
        for game in owned where seen.insert(game.id).inserted {
            result.append(Self(id: game.id, title: game.title, installed: nil, pc: game,
                               product: catalog[game.id] ?? pass[game.id], owned: true,
                               gamePass: active && pass[game.id] != nil))
        }
        if active {
            for game in gamePass where seen.insert(game.id).inserted {
                result.append(Self(id: game.id, title: game.title, installed: nil, pc: nil,
                                   product: game, owned: false, gamePass: true))
            }
        }
        return result
    }

    static func visible(_ games: [Self], query: String, filter: LibraryFilter, sort: LibrarySort) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return games.filter {
            (query.isEmpty || $0.title.localizedStandardContains(query)) &&
            (filter == .all || (filter == .installed && $0.installed != nil) ||
             (filter == .owned && $0.owned) || (filter == .gamePass && $0.gamePass))
        }.sorted {
            if sort == .recentlyPlayed {
                let left = $0.installed?.lastPlayedAt ?? .distantPast
                let right = $1.installed?.lastPlayedAt ?? .distantPast
                if left != right { return left > right }
            }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

struct LibraryControls: View {
    let count: Int
    @Binding var filter: LibraryFilter
    @Binding var sort: LibrarySort

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                heading
                Spacer()
                filters
                sorting
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack { heading; Spacer(); sorting }
                filters
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Your Games").font(.title2.weight(.semibold))
            Text(count.formatted()).font(.title3).foregroundStyle(.secondary)
        }
    }
    private var filters: some View {
        Picker("Filter games", selection: $filter) {
            ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 400)
        .accessibilityIdentifier("xodus.library.filter")
    }
    private var sorting: some View {
        Menu {
            Picker("Sort games", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Sort games by \(sort.rawValue)")
        .accessibilityIdentifier("xodus.library.sort")
    }
}

struct LibraryHero<Artwork: View, Poster: View, Information: View, Actions: View>: View {
    let title: String
    var logos: [CatalogArtworkReference] = []
    var allowsArtworkLoading = true
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let poster: () -> Poster
    @ViewBuilder let information: () -> Information
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork()
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.45),
                                    Color(nsColor: .windowBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 24) {
                poster().frame(width: 100, height: 150).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    LibraryLogoTitle(title: title, references: logos, allowsLoading: allowsArtworkLoading)
                    information()
                    LibraryGlassCluster { actions() }.modifier(LibraryHeroControlSize()).padding(.top, 4)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 56).padding(.bottom, 24)
        }
        .frame(height: 340).clipped()
        .accessibilityElement(children: .contain)
        .modifier(LibraryBackgroundExtension())
    }
}

enum LibraryAccess: String {
    case owned = "Owned", gamePass = "Game Pass"
    var symbol: String { self == .owned ? "checkmark.seal" : "ticket" }
    init?(_ game: LibraryGame) {
        if game.owned { self = .owned }
        else if game.gamePass { self = .gamePass }
        else { return nil }
    }
}

struct LibraryAccessBadge: View {
    let access: LibraryAccess
    var compact = false
    var body: some View {
        Label(access.rawValue, systemImage: access.symbol)
            .font(compact ? .caption : .callout)
            .padding(.horizontal, compact ? 8 : 10).padding(.vertical, 4)
            .modifier(LibraryBadgeMaterial())
    }
}

private struct LibraryBadgeMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.xodusReviewReduceTransparency) private var reviewReduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency || reviewReduceTransparency { content.background(.background, in: Capsule()) }
        else if #available(macOS 26, *) { content.glassEffect(.regular, in: .capsule) }
        else { content.background(.thinMaterial, in: Capsule()) }
    }
}

struct LibraryGameInformation: View {
    var access: LibraryAccess?
    var facts: LibraryCatalogFacts?
    var xbox: LibraryXboxStatsCache.Game?
    var localPlaySeconds: Double? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                if let access { LibraryAccessBadge(access: access, compact: compact) }
                if let facts, !facts.genres.isEmpty {
                    Label(compact ? facts.genres[0] : facts.genres.joined(separator: " / "), systemImage: "tag")
                        .lineLimit(compact ? 1 : 2)
                }
            }
            if !compact {
                if let facts, !facts.capabilities.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        capabilityRow(facts.capabilities)
                        capabilityRow(Array(facts.capabilities.prefix(2)))
                    }
                    .help("Microsoft's PC catalog features, not verified Mac runtime support.")
                }
            }
            if let xbox {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { xboxSummary(xbox, abbreviated: compact) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 5) { xboxSummary(xbox, abbreviated: compact) }
                }
            }
            if let label = Self.playTimeLabel(seconds: localPlaySeconds) {
                Label(label, systemImage: "clock")
            }
        }
        .font(compact ? .caption : .callout).foregroundStyle(.secondary)
    }

    private func capabilityRow(_ values: [LibraryCapability]) -> some View {
        HStack(spacing: 12) { ForEach(values) { Label($0.rawValue, systemImage: $0.symbol) } }
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func xboxSummary(_ xbox: LibraryXboxStatsCache.Game, abbreviated: Bool) -> some View {
        if let time = xbox.playTime { Label(time, systemImage: "clock") }
        Label(abbreviated ? "\(xbox.achievementsUnlocked.formatted()) achievements" : xbox.achievements,
              systemImage: "trophy").help(xbox.achievements)
        if !abbreviated, let friends = xbox.friends {
            Label(friends, systemImage: "person.2").help(xbox.friendHelp)
        }
    }

    static func playTimeLabel(seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0, seconds <= 3_153_600_000 else { return nil }
        if seconds < 60 { return "Less than 1 min played on this Mac" }
        let hours = seconds >= 3600
        let amount = Int(seconds / (hours ? 3600 : 60))
        return "\(amount.formatted()) \(hours ? "h" : "min") played on this Mac"
    }
}

struct LibraryHeroControlSize: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        if enabled { content.controlSize(.large) }
        else { content }
    }
}

struct LibraryImmersion: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.container, edges: .top)
                .toolbarBackground(.hidden, for: .windowToolbar)
        } else { content }
    }
}

struct LibraryGlassCluster<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 12) { HStack(spacing: 12, content: content) }
        } else { HStack(spacing: 12, content: content) }
    }
}

struct LibraryActionStyle: ViewModifier {
    var primary = true
    var usesGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.xodusReviewReduceTransparency) private var reviewReduceTransparency
    func body(content: Content) -> some View {
        if usesGlass, !reduceTransparency, !reviewReduceTransparency, #available(macOS 26, *) {
            if primary { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else if primary { content.buttonStyle(.borderedProminent) }
        else { content.buttonStyle(.bordered) }
    }
}

struct LibraryBackgroundExtension: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.backgroundExtensionEffect() }
        else { content }
    }
}

struct LibraryScrollEdge: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        if enabled, #available(macOS 26, *) { content.scrollEdgeEffectStyle(.soft, for: .top) }
        else { content }
    }
}

struct LibraryCover<Artwork: View, Actions: View, Status: View>: View {
    let title: String
    var openLabel = "Open"
    let open: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let status: () -> Status
    @ViewBuilder let actions: () -> Actions
    @StateObject private var interaction = LibraryCoverInteraction()
    @FocusState private var focused: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private var showsActions: Bool { interaction.hovered || focused || voiceOver }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: open) {
                    artwork().aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).accessibilityLabel("\(openLabel) \(title)")
                actions().controlSize(.small).buttonBorderShape(.capsule).padding(12)
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
            }
            .onHover { interaction.hovered = $0 }
            .focused($focused)
            Text(title).font(.headline).lineLimit(2).frame(minHeight: 36, alignment: .topLeading)
            status().font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
