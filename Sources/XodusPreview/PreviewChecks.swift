// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore

@MainActor
enum PreviewChecks {
    static func run() -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { print("PASS: \(name)") }
            else {
                failures += 1
                FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
            }
        }

        let state = AppState()
        check(ArtAssets.images.count == 6, "Six original fixture image resources load")
        check(state.visibleGames.count == 4, "Library excludes catalog-only and unknown-access fixtures")
        state.query = "moss"
        check(state.visibleGames.isEmpty, "Library search does not broaden to catalog")
        state.navigate(.discover)
        check(state.query.isEmpty && state.visibleGames.count == 6, "Changing scope clears query")
        state.query = "moss"
        check(state.visibleGames.count == 1 && state.visibleGames[0].entitlement == .none,
              "Discover search does not grant entitlement")
        state.query = ""
        state.category = .space
        check(state.visibleGames.map(\.art) == ["orbit"], "Empty-query category browse is scoped")
        state.navigate(.library)
        state.accessFilter = .subscription
        check(state.visibleGames.count == 1, "Library access filter distinguishes subscription")
        state.accessFilter = nil
        state.sortByTitle = true
        check(state.visibleGames.first?.title == "Lumen Harbor", "Title sort is deterministic")

        let game = Fixtures.games[2]
        state.lowSpace = true
        state.enqueue(game)
        check(state.jobs.isEmpty && state.message != nil, "Insufficient space creates no job")
        state.lowSpace = false
        state.message = nil
        state.enqueue(game)
        check(state.jobs.count == 1 && state.destination == .downloads, "Approved fixture plan enqueues once")
        state.enqueue(game)
        check(state.jobs.count == 1, "Duplicate fixture submission creates no second active job")
        if let job = state.jobs.first {
            for _ in 0..<5 { state.updateJob(job.id) { $0.advance() } }
        }
        check(state.installed.contains(game.id), "Only completed fixture job marks installed")
        state.simulateLaunch(game)
        check(state.message?.contains("No game or runtime was started") == true,
              "Simulated launch never claims real gameplay")
        state.connected = false
        check(state.decision(for: game).reason != nil, "Disconnected account blocks action")
        state.reset()
        check(state.jobs.isEmpty && !state.installed.contains(game.id),
              "Fixture reset clears queue and simulated installation")
        print("15 preview checks, \(failures) failures. No backend connected.")
        return failures == 0
    }
}
