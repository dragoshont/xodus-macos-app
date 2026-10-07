// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
enum InstalledGameChecks {
    static func run(check: (Bool, String) -> Void) async throws {
        let config = """
        <?xml version="1.0"?>
        <Game><Identity Name="Fixture.Game" Version="1.2.3.4"/>
        <ShellVisuals DefaultDisplayName="Fixture Installed Game"/><StoreId>FIXTURE00001</StoreId></Game>
        """
        let metadata = try MicrosoftGameConfig.parse(Data(config.utf8))
        check(metadata.identityName == "Fixture.Game" && metadata.version == "1.2.3.4"
              && metadata.storeId == "FIXTURE00001" && metadata.title == "Fixture Installed Game",
              "Installed config reads identity, version, StoreId and display name without a provider")
        let fallback = try MicrosoftGameConfig.parse(Data(config.replacingOccurrences(
            of: "<ShellVisuals DefaultDisplayName=\"Fixture Installed Game\"/>", with: "").utf8))
        check(fallback.title == fallback.identityName, "Missing display name falls back to exact Identity Name")
        for xml in ["", "<Game>", "<Other/>", config.replacingOccurrences(of: "Version=\"1.2.3.4\"", with: ""),
                    config.replacingOccurrences(of: "<StoreId>FIXTURE00001</StoreId>", with: ""),
                    config.replacingOccurrences(of: "1.2.3.4", with: "not-a-version"),
                    "<!DOCTYPE Game [<!ENTITY title 'unexpected'>]><Game>&title;</Game>"] {
            do { _ = try MicrosoftGameConfig.parse(Data(xml.utf8)); check(false, "Invalid installed config is refused") }
            catch { check(error is InstalledGameError, "Invalid installed config is refused") }
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("InstalledGameChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { check(false, "Synthetic installed-game files are cleaned after sessions exit") }
        }
        let folder = root.appendingPathComponent("game folder with spaces")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do { _ = try MicrosoftGameConfig.read(folder: folder); check(false, "Missing config folder is rejected") }
        catch { check(error is InstalledGameError, "Missing config folder is rejected") }
        try Data(config.utf8).write(to: folder.appendingPathComponent("MicrosoftGame.Config"))
        check(try MicrosoftGameConfig.read(folder: folder) == metadata,
              "Case-insensitive MicrosoftGame.Config filename is found in only the selected folder")
        func script(_ name: String, _ contents: String) throws -> URL {
            let file = root.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + contents + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file
        }
        let zero = try script("exit zero.sh", "exit 0")
        let failure = try script("exit three.sh", "exit 3")
        let record = root.appendingPathComponent("arguments.txt")
        let slow = try script("sleep two.sh",
            "printf '%s\\n' \"$#\" \"$1\" \"$PATH\" \"${XODUS_NEUTRAL_SECRET-unset}\" > '\(record.path)'\nsleep 2\nexit 0")
        let file = root.appendingPathComponent("private/installed-games.json")
        let store = InstalledGameStore(file: file)
        let library = InstalledGamesController(store: store, launchingDuration: .milliseconds(100))
        await library.load()
        check(library.loaded && library.games.isEmpty && library.error == nil,
              "Absent private list loads as empty without importing or scanning games")
        await library.importGame(folder: folder, launcher: zero)
        guard let game = library.games.first else { throw InstalledGameError.invalidRegistry }
        check(game.title == metadata.title && game.identityName == metadata.identityName
              && game.version == metadata.version && game.storeId == metadata.storeId
              && game.folder == folder.path && game.launcher == zero.path,
              "Explicit selected folder and launcher persist only their imported identity")
        check(try await store.load() == [game], "Private installed-game JSON round-trips exact fields")
        let filePermissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        check(filePermissions?.intValue == 0o600 && directoryPermissions?.intValue == 0o700,
              "Atomic installed list is 0600 within a 0700 directory")
        await library.importGame(folder: folder, launcher: failure)
        check(library.games.count == 1 && library.games.first?.id == game.id,
              "Reimport updates one local folder entry rather than duplicating it")
        guard let failedGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !condition() {
                guard ContinuousClock.now < deadline else { throw InstalledGameError.launch }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        await library.play(failedGame)
        try await wait { library.runningGameID == nil }
        check(library.playErrors[game.id] == "The game stopped unexpectedly (code 3)." && library.playState == nil,
              "Nonzero fake session exit returns to Play with exact code and retry message")
        await library.importGame(folder: folder, launcher: zero)
        guard let zeroGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        await library.play(zeroGame)
        try await wait { library.runningGameID == nil }
        check(library.playErrors[game.id] == nil && library.playState == nil,
              "Retry's exit zero returns silently to Play without stale failure")
        await library.importGame(folder: folder, launcher: slow)
        guard let slowGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        await library.play(slowGame)
        check(library.playState == .launching && library.runningGameID == slowGame.id,
              "A live fake launcher first publishes Launching")
        await library.play(slowGame)
        try await wait { library.playState == .playing }
        check(library.runningGameID == slowGame.id,
              "A still-alive fake session transitions to Playing and duplicate Play is guarded")
        let lines = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        check(lines.count == 4 && lines[0] == "1" && lines[1].range(
            of: #"^xodus-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"#, options: .regularExpression) != nil
              && lines[2] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" && lines[3] == "unset",
              "Actual bash invocation passes one safe runID and minimal environment, not shell interpolation")
        check(InstalledGamesController.launchEnvironment(["HOME": "/home", "USER": "fixture", "LANG": "en",
                    "PATH": "/wrong", "TOKEN": "secret"]).keys.sorted() == ["HOME", "LANG", "PATH", "USER"],
              "Launch environment excludes unrelated secrets and overrides PATH exactly")
        let fixedID = InstalledGamesController.runID(date: Date(timeIntervalSince1970: 0),
            nonce: UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!)
        check(fixedID == "xodus-19700101T000000Z-abcdef01", "runID uses fixed UTC/POSIX date and lowercase eight-hex nonce")
        let otherFolder = root.appendingPathComponent("other fixture")
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: false)
        try Data(config.utf8).write(to: otherFolder.appendingPathComponent("MicrosoftGame.config"))
        await library.importGame(folder: otherFolder, launcher: failure)
        guard let other = library.games.last else { throw InstalledGameError.invalidRegistry }
        await library.play(other)
        check(library.runningGameID == slowGame.id && library.playErrors[other.id] == nil,
              "A second game's Play cannot overlap the running session")
        let coordinator = ApplicationTerminationCoordinator()
        check(await coordinator.shutdown(session: nil, runtime: nil, installedGames: library)
              && library.applicationTerminating && library.runningGameID == slowGame.id,
              "App termination fences new launches without terminating the running game")
        try await wait { library.runningGameID == nil }
        check(library.playErrors[game.id] == nil, "The fake game finishes naturally after app termination begins")
        library.applicationTerminating = false
        try FileManager.default.removeItem(at: failure)
        await library.play(other)
        check(library.runningGameID == nil && library.playErrors[other.id] == InstalledGameError.missingLauncher.localizedDescription,
              "Missing launcher fails before execution with actionable per-game error")
        await library.remove(other)
        check(!library.games.contains(other) && FileManager.default.fileExists(atPath: otherFolder.path),
              "Remove changes only the saved list and never deletes the installed game folder")
        let reloaded = InstalledGamesController(store: store)
        await reloaded.load()
        check(reloaded.games == library.games && reloaded.loaded,
              "A new app coordinator restores the durable local list without running a game")
        let windows = NSApplication.shared.windows.count
        for width in [CGFloat(700), CGFloat(1100)] {
            let host = NSHostingView(rootView: InstalledGamesView(library: reloaded))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 400)
            host.layoutSubtreeIfNeeded()
            check(host.window == nil && host.fittingSize.width <= width + 1,
                  "Installed rows and native actions fit detached narrow and wide layouts")
        }
        check(NSApplication.shared.windows.count == windows && reloaded.runningGameID == nil,
              "Installed layout checks create no window or launch")
        let corruptFile = root.appendingPathComponent("corrupt.json")
        try Data("not json".utf8).write(to: corruptFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: corruptFile.path)
        let corrupt = InstalledGamesController(store: InstalledGameStore(file: corruptFile))
        await corrupt.load()
        await corrupt.importGame(folder: folder, launcher: zero)
        let retainedCorruptBytes = try Data(contentsOf: corruptFile)
        check(!corrupt.loaded && corrupt.error != nil && corrupt.games.isEmpty
              && retainedCorruptBytes == Data("not json".utf8),
              "Corrupt persistence stays a visible failure and cannot be overwritten as empty success")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let exposed = InstalledGamesController(store: store)
        await exposed.load()
        check(!exposed.loaded && exposed.error != nil,
              "Nonprivate saved-list permissions are refused instead of silently trusting exposed paths")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let alias = root.appendingPathComponent("aliased-list.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        let aliased = InstalledGamesController(store: InstalledGameStore(file: alias))
        await aliased.load()
        check(!aliased.loaded && aliased.error != nil, "Saved-list symlinks are refused without following or replacing their target")
    }
}
