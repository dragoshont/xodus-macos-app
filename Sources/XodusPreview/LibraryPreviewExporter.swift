// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CryptoKit
import Foundation
import XodusCredentials

@MainActor
final class LibraryReviewPresentation: ObservableObject {
    @Published var showGrid = false
}

@MainActor
enum LibraryPreviewExporter {
    static let presentation = LibraryReviewPresentation()
    static var requested: Bool { CommandLine.arguments.contains("--library-preview") }
    static var reduceTransparencyRequested: Bool {
        requested && ProcessInfo.processInfo.environment["XODUS_LIBRARY_PREVIEW_REDUCE_TRANSPARENCY"] == "1"
    }
    static var fixtureRequested: Bool {
        requested && ProcessInfo.processInfo.environment["XODUS_LIBRARY_PREVIEW_SOURCE"] == "fixture"
    }
    private static var started = false

    static func start(state: AppState, session: LiveSession) {
        guard requested, !started else { return }
        started = true
        Task {
            do {
                let grid = CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--library-grid"
                guard (CommandLine.arguments.count == 3 || grid), CommandLine.arguments[1] == "--library-preview",
                      let appearance = ProcessInfo.processInfo.environment["XODUS_LIBRARY_PREVIEW_APPEARANCE"],
                      ["dark", "light"].contains(appearance),
                      let source = ProcessInfo.processInfo.environment["XODUS_LIBRARY_PREVIEW_SOURCE"],
                      ["fixture", "live"].contains(source) else { throw PCGamesError.invalidResponse }
                let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
                let info = try output.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true,
                      output.resolvingSymlinksInPath() == output else { throw PCGamesError.invalidResponse }
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                for _ in 0..<50 where !NSApp.windows.contains(where: { $0.title == "Xodus" }) {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard let window = NSApp.windows.first(where: { $0.title == "Xodus" }) else {
                    throw PCGamesError.invalidResponse
                }
                window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 874), display: true)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                var count = 0
                var distinctBrokerRead = false
                if source == "live" {
                    let broker = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/Xodus/CredentialBroker/XodusCredentialBroker")
                    let manifest = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/XodusCredentialBroker.json")
                    let pin = try JSONDecoder().decode(CredentialBrokerPin.self, from: Data(contentsOf: manifest))
                    guard pin.sha256 == "2c40354c471c7a692cc64eea473a2fe1d34630c140341010ae9967e9742c9381",
                          pin.bytes == 228448 else { throw CredentialFailure.denied }
                    _ = try CredentialIdentity.verifyFile(broker, sha256: pin.sha256, bytes: pin.bytes)
                    await state.installedGames.load()
                    guard state.installedGames.loaded else { throw PCGamesError.invalidResponse }
                    for game in state.installedGames.games { await InstalledGameSizeStore.shared.load(game) }
                    await state.gameOperations.loadGamePassCache()
                    await LibraryXboxStats.shared.loadReadOnly()
                    try await state.pcGames.loadReadOnlyLibraryPreview(broker: CredentialBrokerClient(executable: broker, pin: pin))
                    distinctBrokerRead = true
                    count = state.pcGames.snapshot?.games.count ?? 0
                    await LibraryCatalogArtwork.shared.load(
                        ids: state.installedGames.games.map(\.storeId) + (state.pcGames.snapshot?.games.map(\.id) ?? []),
                        market: session.market, language: session.language)
                    _ = await LibraryCatalogArtwork.shared.preload()
                    for game in state.installedGames.games {
                        _ = await InstalledArtworkStore.shared.image(game: game, splash: true)
                    }
                    _ = try CredentialIdentity.verifyFile(broker, sha256: pin.sha256, bytes: pin.bytes)
                }
                try await Task.sleep(for: .seconds(2))
                if grid {
                    presentation.showGrid = true
                    try await Task.sleep(for: .seconds(1))
                }
                let record: [String: Any] = [
                    "status": "libraryReviewReady", "source": source, "appearance": appearance,
                    "reviewPosition": grid ? "games" : "hero",
                    "pid": ProcessInfo.processInfo.processIdentifier, "width": 1440, "height": 874,
                    "actualWindowWidth": Int(window.frame.width), "actualWindowHeight": Int(window.frame.height),
                    "pcGameCount": count, "distinctSignedBuildReadFrozenBroker": distinctBrokerRead,
                    "cachedXboxStatsGames": source == "live" ? (LibraryXboxStats.shared.cache?.games.count ?? 0) : 0,
                    "statsRefreshCommands": 0,
                    "reduceTransparency": reduceTransparencyRequested ||
                        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                    "systemReduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                    "reviewReducedTransparencySimulation": reduceTransparencyRequested,
                    "installedSizeMeasurements": InstalledGameSizeStore.shared.measurementAttempts,
                    "installedSizesAvailable": state.installedGames.games.filter {
                        InstalledGameSizeStore.shared.value(for: $0) != nil
                    }.count,
                    "publicSizeGames": LibraryCatalogArtwork.shared.images.values.filter { $0.facts.downloadBytes != nil }.count,
                    "brokerWriteDeleteMigrationRequests": 0, "gameServiceActions": 0, "backendConnected": false,
                    "shippingAppReplaced": false, "nativeAuthorizationAllowedByBroker": false
                ]
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                try data.write(to: output.appendingPathComponent("ready.json"), options: .withoutOverwriting)
            } catch {
                FileHandle.standardError.write(Data("Library review stopped: \(error.localizedDescription)\n".utf8))
                NSApp.terminate(nil)
            }
        }
    }
}
