// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
enum GameOperationChecks {
    static func run(check: (Bool, String) -> Void) async throws {
        // macOS temporary URLs retain the /var symlink; the receipt policy correctly refuses it.
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".xodus-game-operation-checks-\(UUID().uuidString)")
        let paths = GameScriptPaths(scripts: root.appendingPathComponent("scripts"),
            processed: root.appendingPathComponent("processed"), logs: root.appendingPathComponent("logs"),
            games: root.appendingPathComponent("Games"), journal: root.appendingPathComponent("private/operation.json"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { check(false, "S3/S5/S6 synthetic files are cleaned after all fake scripts exit") }
        }
        for directory in [paths.scripts, paths.processed, paths.logs, paths.games] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }
        func privateFile(_ url: URL, _ text: String, mode: Int = 0o600) throws {
            try Data(text.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        }
        func script(_ command: GameScriptCommand, _ body: String) throws {
            try privateFile(paths.scripts.appendingPathComponent(command.file), """
                #!/bin/bash
                umask 077
                publish() { cat > "$1.tmp"; mv "$1.tmp" "$1"; }
                \(body)

                """, mode: 0o700)
        }
        func writeMode(_ mode: String) throws { try privateFile(root.appendingPathComponent("mode"), mode) }
        func wait(_ predicate: @MainActor () -> Bool) async throws {
            for _ in 0..<150 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(40))
            }
            throw GameScriptError.timeout
        }
        let runID = InstalledGamesController.runID()
        check(GameScriptPaths.validRunID(runID), "S3/S5/S6 run IDs use the existing generated-only contract")
        for value in ["../status", "xodus-20260101T010101Z-AAAAAAAA", runID + "/../other", "custom-run"] {
            do { _ = try paths.receipt(value, suffix: "status"); check(false, "Receipt paths reject nongenerated IDs") }
            catch { check(true, "Receipt paths reject nongenerated IDs") }
            check(GameScriptFiles.log(runID: value, paths: paths) == nil, "Show log rejects user-controlled paths")
        }
        check(try paths.destination(title: "Game's title / É ! 42", productID: "FIXTURE00001").lastPathComponent
              == "Gamestitle42-Xbox", "S5 destination title is ASCII letters/digits only")
        check(try paths.destination(title: String(repeating: "a", count: 200), productID: "FIXTURE00001")
              .lastPathComponent.count == 101, "S5 destination is bounded")
        let parsed = try GameServiceStatus.parse(Data(#"{"serviceRunning":true,"signedIn":true,"extra":1}"#.utf8))
        check(parsed.signedIn, "S3 status ignores unrelated fields")
        for value in [#"{"serviceRunning":false,"signedIn":true}"#, #"{"serviceRunning":true}"#, #"{"serviceRunning":1,"signedIn":true}"#] {
            do { _ = try GameServiceStatus.parse(Data(value.utf8)); check(false, "S3 incomplete/inconsistent status is not signed in") }
            catch { check(true, "S3 incomplete/inconsistent status is not signed in") }
        }
        for phase in ["preparing", "downloading", "verifying", "configuring", "done", "failed"] {
            let value = try GameScriptProgress.parse(Data("""
                {"phase":"\(phase)","bytesDone":20,"bytesTotal":100,"message":"private diagnostic"}
                """.utf8))
            check(value.bytesDone == 20 && value.bytesTotal == 100 && !value.phase.title.contains("diagnostic"),
                  "S5 real-byte progress has product copy for \(phase)")
        }
        check(try GameScriptProgress.parse(Data(#"{"phase":"preparing","bytesDone":0,"bytesTotal":null}"#.utf8))
            .bytesTotal == nil, "S5 unknown size stays unknown")
        check(try GameScriptProgress.parse(Data(#"{"phase":"preparing","bytesDone":0,"bytesTotal":0}"#.utf8))
            .bytesTotal == 0, "S5 zero total is valid without a percentage denominator")
        for value in [#"{"phase":"invented","bytesDone":0}"#, #"{"phase":"downloading","bytesDone":-1}"#,
                      #"{"phase":"downloading","bytesDone":101,"bytesTotal":100}"#, #"{"phase":"downloading","bytesDone":1.5}"#] {
            do { _ = try GameScriptProgress.parse(Data(value.utf8)); check(false, "S5 malformed progress is refused") }
            catch { check(true, "S5 malformed progress is refused") }
        }
        let signed = root.appendingPathComponent("signed-in")
        try script(.serviceStatus, """
            if [ -f '\(signed.path)' ]; then signed=true; else signed=false; fi
            printf '{"serviceRunning":true,"signedIn":%s}\\n' "$signed" | publish '\(paths.processed.path)'/"$1.result.json"
            printf '0\\n' | publish '\(paths.processed.path)'/"$1.status"
            """)
        try script(.serviceSignIn, """
            touch '\(signed.path)'
            printf '0\\n' | publish '\(paths.processed.path)'/"$1.status"
            """)
        let launcher = root.appendingPathComponent("fixture launcher.sh")
        try privateFile(launcher, "#!/bin/bash\nsleep 1\nexit 0\n", mode: 0o700)
        try script(.install, """
            r="$1"; product="$2"; folder="$3"; receipts='\(paths.processed.path)'
            printf '%s\\n' "$#" "$r" "$product" "$folder" "$PATH" "${XODUS_NEUTRAL_SECRET-unset}" > '\(root.path)/arguments'
            printf 'Synthetic operation log\\n' > '\(paths.logs.path)'/"$r.stderr.log"
            mode="$(cat '\(root.path)/mode')"
            if [ "$mode" = missing ]; then exit 9; fi
            if [ "$mode" = mismatch ]; then printf '0\\n' | publish "$receipts/$r.status"; exit 3; fi
            trap 'printf "14\\n" | publish "$receipts/$r.status"; exit 14' TERM
            printf '{"phase":"downloading","bytesDone":20,"bytesTotal":100}\\n' | publish "$receipts/$r.progress.json"
            if [ "$mode" = slow ]; then while :; do sleep 0.1; done; fi
            if [ "$mode" = invalidprogress ]; then
                printf '{"phase":"downloading","bytesDone":-1}\\n' | publish "$receipts/$r.progress.json"
                while :; do sleep 0.1; done
            fi
            case "$mode" in 10|11|12|13|14) printf '%s\\n' "$mode" | publish "$receipts/$r.status"; exit "$mode";; esac
            mkdir -p "$folder"
            if [ "$mode" != badconfig ]; then
                printf '<Game><Identity Name="Fixture.Game" Version="1.2.3.4"/><ShellVisuals DefaultDisplayName="Fixture Game"/><StoreId>%s</StoreId></Game>' "$product" > "$folder/MicrosoftGame.config"
            fi
            if [ "$mode" = wrongid ]; then resultid=OTHER0000001; else resultid="$product"; fi
            printf '{"folder":"%s","launcher":"%s","storeId":"%s","title":"Ignored result title","bottle":"ignored","contentId":"ignored","bytesOnDisk":42}\\n' "$folder" '\(launcher.path)' "$resultid" | publish "$receipts/$r.result.json"
            printf '0\\n' | publish "$receipts/$r.status"
            exit 0
            """)
        try script(.uninstall, """
            mode="$(cat '\(root.path)/mode')"
            if [ "$mode" = preservefail ]; then code=20; else code=0; fi
            printf '%s\\n' "$code" | publish '\(paths.processed.path)'/"$1.status"
            exit "$code"
            """)
        _ = try GameScriptFiles.script(.serviceStatus, paths: paths)
        _ = try GameScriptFiles.read(paths.journal, missingAllowed: true)
        let store = InstalledGameStore(file: root.appendingPathComponent("registry/installed-games.json"))
        let installed = InstalledGamesController(store: store, launchingDuration: .milliseconds(50))
        let operations = GameOperationsController(installed: installed, paths: paths)
        check(operations.serviceStatus == nil && !operations.serviceBusy && operations.operation == nil
              && !FileManager.default.fileExists(atPath: paths.journal.path),
              "S3/S5/S6 construction performs no script, credential or journal I/O")
        await installed.load()
        await operations.restore()
        operations.refreshService()
        await operations.waitForService()
        if let error = operations.serviceError { print("NEUTRAL service-status failure: \(error)") }
        check(operations.serviceStatus?.signedIn == false && operations.serviceError == nil,
              "S3 explicit status reads only the service-owned receipt")
        operations.signInForGames()
        await operations.waitForService()
        if let error = operations.serviceError { print("NEUTRAL service-signin failure: \(error)") }
        check(operations.serviceStatus?.signedIn == true && !installed.serviceSignInActive,
              "S3 explicit sign-in is followed by a fresh status check; no token transfer")
        let game = PCGame(id: "FIXTURE00001", title: "Fixture Game", artwork: nil)
        func install(_ candidate: PCGame = game) async throws {
            await operations.prepareInstall(candidate)
            guard let consent = operations.installConsent else { throw GameScriptError.invalidDestination }
            operations.confirmInstall(consent)
            await operations.waitForMutation()
        }
        try writeMode("slow")
        await operations.prepareInstall(game)
        if let error = operations.error { print("NEUTRAL consent failure: \(error)") }
        guard let first = operations.installConsent else { throw GameScriptError.invalidDestination }
        check(first.destination.lastPathComponent == "FixtureGame-Xbox" && first.freeBytes >= 0
              && operations.operation == nil, "S5 consent has real free space and causes no script side effect")
        operations.installConsent = nil
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("arguments").path),
              "S5 cancelling consent does not start installation")
        await operations.prepareInstall(game)
        guard let consent = operations.installConsent else { throw GameScriptError.invalidDestination }
        operations.confirmInstall(consent)
        try await wait { operations.progress?.bytesDone == 20 }
        check(operations.isBusy && !operations.canQuit && installed.mutationActive
              && !operations.canStartMutation && !operations.canSignIn,
              "S5 one mutation reserves registration, service restart and normal Quit")
        let activeID = operations.operation?.id
        await operations.prepareInstall(game)
        operations.signInForGames()
        check(operations.installConsent == nil && operations.operation?.id == activeID && !operations.serviceSigningIn,
              "S3/S5 commands cannot bypass the one-mutation guard while an install is active")
        let termination = ApplicationTerminationCoordinator()
        let session = LiveSession()
        check(!(await termination.shutdown(session: session, runtime: nil,
                                            installedGames: installed, gameOperations: operations)),
              "S5 normal Quit is refused before disconnecting or abandoning an operation")
        check(!installed.applicationTerminating, "S5 refused Quit leaves existing Play/controller state intact")
        let args = try String(contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8).components(separatedBy: "\n")
        check(args[0] == "3" && GameScriptPaths.validRunID(args[1]) && args[2] == game.id
              && args[3] == consent.destination.path && args[4] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
              && args[5] == "unset", "S5 script receives exact argv and minimal environment without inherited secrets")
        await operations.cancelInstall()
        await operations.waitForMutation()
        check(!operations.isBusy && !installed.mutationActive && operations.error == GameScriptError.failed(14).localizedDescription
              && operations.log != nil && installed.games.isEmpty,
              "S5 SIGTERM joins the script, consumes code 14 and keeps partial files unregistered")
        try writeMode("success")
        try await install()
        guard let imported = installed.games.first else { throw GameScriptError.invalidReceipt }
        check(imported.storeId == game.id && imported.title == "Fixture Game"
              && imported.folder == consent.destination.path && imported.launcher == launcher.path
              && operations.error == nil && installed.launchableIDs.contains(imported.id),
              "S5 status zero ignores extra result fields and registers only from config validation and durable save")
        let reloaded = try await store.load()
        check(reloaded == installed.games, "S5 validated installation survives a registry reload")
        await installed.play(imported)
        check(installed.runningGameID == imported.id && !operations.canSignIn,
              "S3 game-service restart is disabled while a game is running")
        await operations.prepareInstall(game, repairing: imported)
        operations.prepareUninstall(imported)
        check(operations.installConsent == nil && operations.uninstallConsent == nil,
              "S6 repair and uninstall cannot target a running game")
        try await wait { installed.runningGameID == nil }
        await installed.waitForSessionPersistence()
        guard let played = installed.games.first else { throw GameScriptError.invalidReceipt }
        let history = played.lastPlayedAt
        await operations.prepareInstall(game, repairing: played)
        guard let repair = operations.installConsent else { throw GameScriptError.invalidDestination }
        check(repair.destination.path == played.folder && repair.installedID == played.id,
              "S6 repair consents to the exact existing folder and entry")
        operations.confirmInstall(repair)
        await operations.waitForMutation()
        check(installed.games.first?.id == played.id && installed.games.first?.lastPlayedAt == history
              && installed.games.first?.lastSessionSeconds == played.lastSessionSeconds,
              "S6 repair preserves registration identity and own-session history")
        try writeMode("preservefail")
        guard let repaired = installed.games.first else { throw GameScriptError.invalidReceipt }
        operations.prepareUninstall(repaired)
        operations.confirmUninstall(repaired)
        await operations.waitForMutation()
        check(installed.games.count == 1 && operations.error?.contains("couldn't be preserved") == true,
              "S6 code 20 explicitly preserves the installed entry after save-preservation refusal")
        try writeMode("success")
        operations.prepareUninstall(repaired)
        operations.confirmUninstall(repaired)
        await operations.waitForMutation()
        check(installed.games.isEmpty && !operations.isBusy
              && FileManager.default.fileExists(atPath: repaired.folder),
              "S6 only status zero removes registration; app itself never deletes game files")
        for code in [10, 11, 12, 13, 14] {
            try writeMode(String(code))
            try await install()
            check(operations.error == GameScriptError.failed(code).localizedDescription && operations.log != nil
                  && installed.games.isEmpty && !operations.isBusy,
                  "S5 code \(code) has a specific error/recovery and cannot become installed")
        }
        for mode in ["missing", "mismatch", "invalidprogress"] {
            try writeMode(mode)
            try await install()
            check(operations.error != nil && operations.log != nil && installed.games.isEmpty
                  && !operations.isBusy && operations.canQuit,
                  "S5 \(mode) is a joined failure with Show log, not a registration or orphan")
        }
        let other = PCGame(id: "FIXTURE00002", title: "Second Fixture", artwork: nil)
        try writeMode("badconfig")
        try await install(other)
        check(installed.games.isEmpty && operations.recoveryRequired && operations.error != nil,
              "S5 a successful script cannot bypass missing MicrosoftGame.config")
        await operations.reconcile()
        check(installed.games.isEmpty && operations.recoveryRequired,
              "S5 receipt reconciliation never bypasses the shared import validator")
        let journal = GameOperationJournal(file: paths.journal)
        let saved = try await journal.load()
        check(saved?.productID == other.id, "S5 interrupted registration retains its exact pending receipt")
        let recordMode = (try FileManager.default.attributesOfItem(atPath: paths.journal.path)[.posixPermissions] as? NSNumber)?.intValue
        let dirMode = (try FileManager.default.attributesOfItem(atPath: paths.journal.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue
        check(recordMode == 0o600 && dirMode == 0o700, "S5 pending journal is atomic/private with 0600/0700")
        installed.releaseMutation()
        let recovered = GameOperationsController(installed: installed, paths: paths)
        await recovered.restore()
        check(recovered.recoveryRequired && recovered.operation?.id == saved?.id && !recovered.canStartMutation,
              "S5 reopening a pending operation does not replay scripts or silently permit another mutation")
        let recoveredFolder = try paths.destination(title: other.title, productID: other.id)
        try privateFile(recoveredFolder.appendingPathComponent("MicrosoftGame.config"),
            "<Game><Identity Name=\"Fixture.Second\" Version=\"1.2.3.4\"/><StoreId>\(other.id)</StoreId></Game>")
        await recovered.reconcile()
        check(!recovered.recoveryRequired && !recovered.isBusy && installed.games.first?.storeId == other.id,
              "S5 explicit reconciliation can finish validated registration without another script invocation")
        let cancellationRunner = GameScriptRunner(paths: paths)
        let cancelledRun = InstalledGamesController.runID()
        await cancellationRunner.cancel(runID: cancelledRun)
        let cancelledBeforeStart = try await cancellationRunner.run(command: .install, runID: cancelledRun,
            arguments: [other.id, recoveredFolder.path])
        let cancelledReceipt = try paths.receipt(cancelledRun, suffix: "status")
        check(cancelledBeforeStart.code == 14
              && !FileManager.default.fileExists(atPath: cancelledReceipt.path),
              "S5 cancellation before Process.run does not spawn a script or invent a persisted receipt")
        for arguments in [[], ["invalid", recoveredFolder.path], [other.id, root.path + "/../escape"]] {
            do {
                _ = try await cancellationRunner.run(command: .install, runID: InstalledGamesController.runID(), arguments: arguments)
                check(false, "S5 command arguments are validated before launch")
            } catch { check(true, "S5 command arguments are validated before launch") }
        }
        do {
            _ = try await cancellationRunner.run(command: .uninstall, runID: InstalledGamesController.runID(),
                                                 arguments: [other.id, root.path])
            check(false, "S6 uninstall is confined to the approved game root")
        } catch { check(true, "S6 uninstall is confined to the approved game root") }
        try writeMode("wrongid")
        guard let current = installed.games.first else { throw GameScriptError.invalidReceipt }
        await recovered.prepareInstall(other, repairing: current)
        guard let mismatchRepair = recovered.installConsent else { throw GameScriptError.invalidDestination }
        recovered.confirmInstall(mismatchRepair)
        await recovered.waitForMutation()
        check(recovered.recoveryRequired && recovered.error != nil && installed.games.first?.storeId == other.id,
              "S5/S6 result StoreId mismatch cannot replace an existing registration")
        await recovered.reconcile()
        check(recovered.recoveryRequired && installed.games.first?.id == current.id,
              "S5/S6 recovery cannot promote a mismatched result")
        let badID = root.appendingPathComponent("bad-id.status")
        try privateFile(badID, "0")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: badID.path)
        do { _ = try GameScriptFiles.read(badID); check(false, "Script receipts require private mode") }
        catch { check(true, "Script receipts require private mode") }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("receipt-link"), withDestinationURL: badID)
        do { _ = try GameScriptFiles.read(root.appendingPathComponent("receipt-link")); check(false, "Symlink receipts are refused") }
        catch { check(true, "Symlink receipts are refused") }
        let oversize = root.appendingPathComponent("oversized-result.json")
        try privateFile(oversize, String(repeating: "x", count: 65_537))
        do { _ = try GameScriptFiles.read(oversize); check(false, "S5 receipt reading is bounded at 64KiB") }
        catch { check(true, "S5 receipt reading is bounded at 64KiB") }
        for code in ["-1", "256", "0junk", ""] {
            do { _ = try GameScriptFiles.status(Data(code.utf8)); check(false, "S5 malformed terminal status is explicit") }
            catch { check(true, "S5 malformed terminal status is explicit") }
        }
        let windows = NSApplication.shared.windows.count
        for width in [CGFloat(700), CGFloat(1100)] {
            let host = NSHostingView(rootView: GameOperationProgressView(operations: recovered))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 400)
            host.layoutSubtreeIfNeeded()
            check(host.frame.width == width && NSApplication.shared.windows.count == windows,
                  "S5 native progress/recovery lays out without presenting a window or starting a script")
        }
        installed.releaseMutation()
    }
}
