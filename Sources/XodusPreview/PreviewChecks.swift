// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore

@MainActor
enum PreviewChecks {
    static func run() -> Bool {
        var count = 0, failures = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1
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
        for destination in Destination.allCases {
            state.query = "prior scope"
            state.accessFilter = .subscription
            state.sortByTitle = true
            state.category = .space
            state.navigationSelection.wrappedValue = destination
            check(state.destination == destination && state.navigationSelection.wrappedValue == destination
                  && state.query.isEmpty && state.accessFilter == nil && !state.sortByTitle
                  && state.category == .all && !state.showingAccount && !state.showingWelcome,
                  "Native toolbar binding preserves \(destination.rawValue) routing and clears only browse scope")
        }
        let live = LiveSession()
        check(!state.fixtureMode, "Default application mode does not present fixture games")
        check(live.products.isEmpty, "Live catalog never starts with invented titles")
        check(live.authentication == nil, "Live account does not start with simulated sign-in")
        check(live.activity.jobs.isEmpty, "Live activity does not start with simulated jobs")
        check(!live.canSignIn, "Sign-in is disabled until backend capability negotiation")
        check(!live.supports(.launch) && !live.supports(.plan), "Live gameplay and installation fail closed")
        check(!live.signInPending && !live.accountBusy, "No unattended native sign-in begins")
        check(live.diagnosticPreview == nil, "No diagnostics or raw engine text are captured at startup")
        check(live.phase == .disconnected, "Presentation checks do not contact Xodus or Keychain")
        NativeUIChecks.run(check: check)
        print("\(count) preview checks, \(failures) failures. No backend connected.")
        return failures == 0
    }
}
