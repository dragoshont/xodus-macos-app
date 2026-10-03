// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI
import XodusCore

enum Destination: String, CaseIterable, Identifiable {
    case library = "Library", discover = "Discover", downloads = "Downloads"
    var id: String { rawValue }
}

enum BrowseCategory: String, CaseIterable, Identifiable {
    case all = "All worlds", adventure = "Quiet adventures", space = "Space", puzzles = "Puzzles"
    var id: String { rawValue }

    func includes(_ game: Game) -> Bool {
        switch self {
        case .all: true
        case .adventure: ["harbor", "signal", "tide"].contains(game.art)
        case .space: game.art == "orbit"
        case .puzzles: ["ridge", "moss"].contains(game.art)
        }
    }
}

@MainActor
final class SheetInteraction: ObservableObject {
    @Published var showInstall = false
    @Published var acceptsExperimental = false
    @Published var cancelled = false
}

@MainActor
final class AppState: ObservableObject {
    @Published var destination: Destination = .library
    @Published var query = ""
    @Published var sortByTitle = false
    @Published var accessFilter: Entitlement? = nil
    @Published var category: BrowseCategory = .all
    @Published var inventory: InventoryState = .complete
    @Published var connected = true
    @Published var showingWelcome = false
    @Published var selectedGame: Game?
    @Published var jobs: [FixtureJob] = []
    @Published var installed = Set(Fixtures.games.filter(\.initiallyInstalled).map(\.id))
    @Published var lowSpace = false
    @Published var message: String?

    var visibleGames: [Game] {
        guard inventory != .empty && inventory != .failed else { return [] }
        let games = Fixtures.games.filter {
            let inScope = destination == .discover || $0.entitlement == .purchase || $0.entitlement == .subscription
            let matchesAccess = destination != .library || accessFilter == nil || $0.entitlement == accessFilter
            let matchesCategory = destination != .discover || !query.isEmpty || category.includes($0)
            return inScope && matchesAccess && matchesCategory
                && (query.isEmpty || $0.title.localizedStandardContains(query))
        }
        return sortByTitle ? games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : games
    }

    func navigate(_ value: Destination) {
        destination = value
        query = ""
        accessFilter = nil
        sortByTitle = false
        category = .all
    }

    func decision(for game: Game) -> InstallDecision {
        guard connected else { return .blocked("Connect the fixture account first.") }
        return ActionPolicy.evaluate(game, inventory: inventory, now: Fixtures.checkedAt,
                                     fingerprint: Fixtures.fingerprint)
    }

    func enqueue(_ game: Game) {
        guard decision(for: game) == .allowed, let package = game.package else {
            message = decision(for: game).reason ?? "The fixture package is unavailable."
            return
        }
        guard InstallPlan(game: game, package: package,
                          availableBytes: availableBytes).hasEnoughSpace else {
            message = "Not enough simulated storage. No job was created."
            return
        }
        guard !installed.contains(game.id),
              !jobs.contains(where: { $0.gameID == game.id && !$0.phase.isTerminal }) else {
            message = "This fixture is already installed or in the simulated queue."
            return
        }
        jobs.append(FixtureJob(gameID: game.id))
        selectedGame = nil
        navigate(.downloads)
    }

    var availableBytes: Int64 { (lowSpace ? 5 : 120) * Fixtures.gigabyte }

    func updateJob(_ id: UUID, operation: (inout FixtureJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            message = "The fixture job is no longer in the queue."
            return
        }
        operation(&jobs[index])
        if jobs[index].phase == .completed { installed.insert(jobs[index].gameID) }
    }

    func simulateLaunch(_ game: Game) {
        guard installed.contains(game.id), decision(for: game) == .allowed else {
            message = decision(for: game).reason ?? "This fixture is not installed."
            return
        }
        message = "Simulation only: \(game.title) would launch here. No game or runtime was started."
    }

    func reset() {
        jobs = []
        installed = Set(Fixtures.games.filter(\.initiallyInstalled).map(\.id))
        inventory = .complete
        lowSpace = false
        connected = true
        navigate(.library)
        selectedGame = nil
        showingWelcome = false
        message = nil
    }
}
