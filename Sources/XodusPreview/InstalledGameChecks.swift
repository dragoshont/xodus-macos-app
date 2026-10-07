// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import Foundation
import ImageIO
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
        let visuals = """
        <Game><Identity Name="Fixture.Game" Version="1.2.3.4"/><ShellVisuals
        DefaultDisplayName="Fixture Installed Game" PublisherDisplayName="Fixture Publisher"
        Square480x480Logo="Resources\\large.png" Square150x150Logo="Resources\\small.png"
        StoreLogo="Resources\\store.png" SplashScreenImage="Resources\\splash.png"/>
        <StoreId>FIXTURE00001</StoreId></Game>
        """
        let enriched = try MicrosoftGameConfig.parse(Data(visuals.utf8))
        check(enriched.publisher == "Fixture Publisher" && enriched.tileArt ==
            ["Resources\\large.png", "Resources\\small.png", "Resources\\store.png"]
            && enriched.splashArt == "Resources\\splash.png",
              "AC1.1/1.2: ShellVisuals retains publisher and exact ordered Windows-style artwork paths")
        let resources = folder.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: false)
        func png(width: Int) throws -> Data {
            guard let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage() else { throw ArtworkLoadError.invalidImage }
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else {
                throw ArtworkLoadError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ArtworkLoadError.invalidImage }
            return bytes as Data
        }
        let tiny = try png(width: 8)
        try tiny.write(to: resources.appendingPathComponent("large.png"))
        try png(width: 4).write(to: resources.appendingPathComponent("small.png"))
        try png(width: 2).write(to: resources.appendingPathComponent("store.png"))
        let selected = InstalledArtworkPolicy.image(folder: folder, candidates: enriched.tileArt, maxDimension: 480)
        check(selected?.width == 8, "AC1.1: Valid Square480 art is preferred without using a catalog")
        try Data("broken".utf8).write(to: resources.appendingPathComponent("large.png"))
        check(InstalledArtworkPolicy.image(folder: folder, candidates: enriched.tileArt, maxDimension: 480)?.width == 4,
              "AC1.1: Invalid Square480 falls back to valid Square150")
        try FileManager.default.removeItem(at: resources.appendingPathComponent("small.png"))
        check(InstalledArtworkPolicy.image(folder: folder, candidates: enriched.tileArt, maxDimension: 480)?.width == 2,
              "AC1.1: Missing Square150 falls back to StoreLogo")
        let art = try InstalledArtworkPolicy.read(folder: folder, relative: "Resources\\store.png")
        check(try InstalledArtworkPolicy.decode(art, maxDimension: 1).width == 1,
              "AC1.1: Local decode is downsampled to its presentation budget")
        for path in ["../outside.png", "/outside.png", "\\outside.png", "C:\\outside.png",
                     "Resources/../store.png", "Resources//store.png", "Resources/./store.png",
                     "Resources/store.gif", "Resources/store.png\u{0}"] {
            check(InstalledArtworkPolicy.components(path) == nil, "AC1.6: Unsafe or non-PNG/JPEG local art path is rejected")
        }
        let outside = root.appendingPathComponent("outside.png")
        try tiny.write(to: outside)
        try FileManager.default.createSymbolicLink(at: resources.appendingPathComponent("link.png"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked"), withDestinationURL: resources)
        for path in ["Resources/link.png", "linked/store.png", "Resources"] {
            do { _ = try InstalledArtworkPolicy.read(folder: folder, relative: path); check(false, "AC1.6: Symlink/nonregular artwork is refused") }
            catch { check(true, "AC1.6: Symlink/nonregular artwork is refused") }
        }
        let tooLarge = resources.appendingPathComponent("huge.png")
        try Data(repeating: 0, count: InstalledArtworkPolicy.maximumBytes).write(to: tooLarge)
        check(try InstalledArtworkPolicy.read(folder: folder, relative: "Resources/huge.png").count == 8 * 1024 * 1024,
              "AC1.6: Exact 8MiB byte boundary is accepted for bounded reading")
        try Data(repeating: 0, count: InstalledArtworkPolicy.maximumBytes + 1).write(to: tooLarge)
        do { _ = try InstalledArtworkPolicy.read(folder: folder, relative: "Resources/huge.png"); check(false, "AC1.6: Artwork above 8MiB is refused") }
        catch { check(true, "AC1.6: Artwork above 8MiB is refused") }
        try InstalledArtworkPolicy.validatePixels(width: 4000, height: 4000)
        check(true, "AC1.6: Exact 16M-pixel boundary passes")
        for dimensions in [(4001, 4000), (0, 1), (Int.max, Int.max)] {
            do { try InstalledArtworkPolicy.validatePixels(width: dimensions.0, height: dimensions.1); check(false, "AC1.6: Unsafe pixel dimensions fail before decode") }
            catch { check(true, "AC1.6: Unsafe pixel dimensions fail before decode") }
        }
        var pixelBomb = tiny
        for offset in [16, 20] {
            pixelBomb.replaceSubrange(offset..<(offset + 4), with: [UInt8(0), 0, 16, 0])
        }
        var crc: UInt32 = 0xffffffff
        for byte in pixelBomb[12..<29] {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        crc ^= 0xffffffff
        pixelBomb.replaceSubrange(29..<33, with: [
            UInt8(truncatingIfNeeded: crc >> 24), UInt8(truncatingIfNeeded: crc >> 16),
            UInt8(truncatingIfNeeded: crc >> 8), UInt8(truncatingIfNeeded: crc)
        ])
        do { _ = try InstalledArtworkPolicy.decode(pixelBomb, maxDimension: 480); check(false, "AC1.6: Invalid oversized PNG header never produces a decoded image") }
        catch {
            check(error as? ArtworkLoadError == .oversized || error as? ArtworkLoadError == .invalidImage,
                  "AC1.6: Invalid oversized PNG header never produces a decoded image")
        }
        check(InstalledArtworkPolicy.image(folder: folder, candidates: ["missing.png", "Resources/huge.png"], maxDimension: 480) == nil,
              "AC1.1: Missing/invalid artwork silently preserves the system-symbol fallback")
        try Data(visuals.utf8).write(to: folder.appendingPathComponent("MicrosoftGame.Config"))
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
        let library = InstalledGamesController(store: store, launchingDuration: .milliseconds(100),
                                               logDirectory: root.appendingPathComponent("logs"))
        await library.load()
        check(library.loaded && library.games.isEmpty && library.error == nil,
              "Absent private list loads as empty without importing or scanning games")
        await library.importGame(folder: folder, launcher: zero)
        guard let game = library.games.first else { throw InstalledGameError.invalidRegistry }
        check(game.publisher == "Fixture Publisher" && game.lastPlayedAt == nil && library.continuingGame == nil,
              "AC1.2/1.4: Import stores publisher but never invents a played session or hero")
        check(game.title == metadata.title && game.identityName == metadata.identityName
              && game.version == metadata.version && game.storeId == metadata.storeId
              && game.folder == folder.path && game.launcher == zero.path,
              "Explicit selected folder and launcher persist only their imported identity")
        check(try await store.load() == [game], "Private installed-game JSON round-trips exact fields")
        let legacyData = try JSONEncoder().encode([game])
        guard var legacy = try JSONSerialization.jsonObject(with: legacyData) as? [[String: Any]] else {
            throw InstalledGameError.invalidRegistry
        }
        for key in ["publisher", "lastPlayedAt", "lastSessionSeconds"] { legacy[0].removeValue(forKey: key) }
        let oldEntry = try JSONDecoder().decode([InstalledGame].self, from: JSONSerialization.data(withJSONObject: legacy))[0]
        check(oldEntry.publisher == nil && oldEntry.lastPlayedAt == nil && oldEntry.lastSessionSeconds == nil,
              "AC1.2/1.6: Legacy registry entries without new fields decode unchanged")
        legacy[0]["lastSessionSeconds"] = "invalid"
        do { _ = try JSONDecoder().decode([InstalledGame].self, from: JSONSerialization.data(withJSONObject: legacy)); check(false, "AC1.2: Wrong-type new history fields are refused") }
        catch { check(true, "AC1.2: Wrong-type new history fields are refused") }
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
        await library.waitForSessionPersistence()
        let failedSession = try await store.load().first
        check(failedSession?.lastPlayedAt != nil && failedSession?.lastSessionSeconds.map { $0 >= 0 } == true,
              "AC1.3: A short-lived Xodus-launched failure records its start and measured lifetime atomically")
        check(library.playErrors[game.id] == "The game stopped unexpectedly (code 3)." && library.playState == nil,
              "Nonzero fake session exit returns to Play with exact code and retry message")
        check(library.playLogs[game.id] == nil, "AC2.3: A nonzero session without its stderr file offers no Show log")
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: false)
        let loggedFailure = try script("logged failure.sh",
            "printf 'neutral launch error\\n' > '\(logs.path)/'\"$1\"'.stderr.log'\nexit 3")
        await library.importGame(folder: folder, launcher: loggedFailure)
        guard let loggedGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        await library.play(loggedGame)
        try await wait { library.playLogs[game.id] != nil }
        check(library.playLogs[game.id]?.deletingLastPathComponent().path == logs.path
              && library.playErrors[game.id] == "The game stopped unexpectedly (code 3).",
              "AC2.3: Nonzero script exit exposes only its existing generated-session stderr file")
        await library.waitForSessionPersistence()
        await library.importGame(folder: folder, launcher: zero)
        guard let zeroGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        await library.play(zeroGame)
        try await wait { library.runningGameID == nil }
        check(library.playErrors[game.id] == nil && library.playState == nil,
              "Retry's exit zero returns silently to Play without stale failure")
        check(library.playLogs[game.id] == nil, "AC2.3: Retry clears the previous session log action")
        await library.importGame(folder: folder, launcher: slow)
        guard let slowGame = library.games.first else { throw InstalledGameError.invalidRegistry }
        await library.play(slowGame)
        check(library.playState == .launching && library.runningGameID == slowGame.id,
              "A live fake launcher first publishes Launching")
        await library.play(slowGame)
        try await wait { library.playState == .playing }
        await library.waitForSessionPersistence()
        check(try await store.load().first?.lastPlayedAt == library.games.first?.lastPlayedAt
              && library.games.first?.lastSessionSeconds == nil && library.continuingGame?.id == slowGame.id,
              "AC1.3/1.4: Launch start is durable before exit and drives only the imported game hero")
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
        check(InstalledGamesController.sessionLog(runID: fixedID, directory: root)?.lastPathComponent ==
              "xodus-19700101T000000Z-abcdef01.stderr.log",
              "AC2.3: Log path contains only the app-generated runID and fixed stderr suffix")
        for input in ["../secret", fixedID + "/file", fixedID + "\n", "xodus-20260101T000000Z-ABCDEF00"] {
            check(InstalledGamesController.sessionLog(runID: input, directory: root) == nil,
                  "AC2.3: Arbitrary or path-bearing log runIDs are refused")
        }
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
        await library.waitForSessionPersistence()
        let completedSession = try await store.load().first { $0.id == slowGame.id }
        check(completedSession?.lastSessionSeconds.map { (1.8...4).contains($0) } == true,
              "AC1.3/1.6: Session end persists measured fake-process seconds despite another game import")
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
            let host = NSHostingView(rootView: InstalledGamesView(library: reloaded,
                operations: GameOperationsController(installed: reloaded), allowsArtworkLoading: false))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 400)
            host.layoutSubtreeIfNeeded()
            check(host.window == nil && host.fittingSize.width <= width + 1,
                  "Installed rows and native actions fit detached narrow and wide layouts")
        }
        check(NSApplication.shared.windows.count == windows && reloaded.runningGameID == nil,
              "Installed layout checks create no window or launch")
        var older = game
        older.lastPlayedAt = Date(timeIntervalSince1970: 10)
        var newer = InstalledGame(id: UUID(), title: "Second Fixture", identityName: "Fixture.Second",
            version: game.version, storeId: game.storeId, folder: otherFolder.path,
            launcher: zero.path, importedAt: game.importedAt)
        newer.lastPlayedAt = Date(timeIntervalSince1970: 20)
        try await store.save([older, newer])
        let ordered = InstalledGamesController(store: store)
        await ordered.load()
        check(ordered.continuingGame?.id == newer.id, "AC1.4/1.6: Most recent imported launchable entry wins hero selection")
        newer = InstalledGame(id: newer.id, title: newer.title, identityName: newer.identityName,
            version: newer.version, storeId: newer.storeId, folder: newer.folder,
            launcher: failure.path, importedAt: newer.importedAt, lastPlayedAt: Date(timeIntervalSince1970: 30))
        try await store.save([older, newer])
        let unavailable = InstalledGamesController(store: store)
        await unavailable.load()
        check(unavailable.continuingGame?.id == older.id,
              "AC1.4: An unavailable launcher is excluded even when its recorded play is newest")
        try await store.save([older])
        let resilient = InstalledGamesController(store: store, launchingDuration: .milliseconds(100),
                                                logDirectory: root.appendingPathComponent("logs"))
        await resilient.load()
        await resilient.importGame(folder: folder, launcher: slow)
        guard let resilientGame = resilient.games.first else { throw InstalledGameError.invalidRegistry }
        await resilient.play(resilientGame)
        await resilient.waitForSessionPersistence()
        let beforeCorruption = try Data(contentsOf: file)
        try Data("corrupt".utf8).write(to: file)
        try await wait { resilient.runningGameID == nil }
        await resilient.waitForSessionPersistence()
        check(resilient.playState == nil && resilient.playErrors[resilientGame.id] == nil
              && resilient.historyError != nil,
              "AC1.3: A history save failure never blocks termination or misreports game exit")
        try beforeCorruption.write(to: file)
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
