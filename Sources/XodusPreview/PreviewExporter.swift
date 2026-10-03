// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import XodusCore

@MainActor
enum PreviewExporter {
    private static var started = false
    private static var fixtureExport = true

    static func startIfRequested(state: AppState) {
        guard !started, let flag = CommandLine.arguments.firstIndex(of: "--export-preview")
                ?? CommandLine.arguments.firstIndex(of: "--export-live") else { return }
        started = true
        fixtureExport = CommandLine.arguments[flag] == "--export-preview"
        guard CommandLine.arguments.indices.contains(flag + 1) else {
            fail("Own-view export requires an explicit output directory")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch { fail("Cannot create preview export directory: \(error.localizedDescription)") }
        exportScreen(0, state: state, directory: directory)
    }

    private static func exportScreen(_ index: Int, state: AppState, directory: URL) {
        let screens: [Destination] = [.library, .discover, .downloads]
        guard screens.indices.contains(index) else {
            print("Exported 3 native \(fixtureExport ? "fixture" : "disconnected live-shell") views. No desktop or other app capture.")
            exit(0)
        }
        let screen = screens[index]
        state.navigate(screen)
        if fixtureExport && screen == .downloads {
            state.jobs = [
                FixtureJob(gameID: Fixtures.games[2].id, phase: .verifying),
                FixtureJob(gameID: Fixtures.games[1].id, phase: .failed)
            ]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && ($0.title == "Xodus" || $0.title.contains("Fixture Preview"))
            }), let view = window.contentView?.superview else {
                fail("Native fixture window was not available for its own view export")
            }
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                fail("AppKit could not allocate a native view bitmap")
            }
            // This renders only our own NSView hierarchy, never reads the desktop framebuffer.
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                fail("AppKit native view export produced no PNG")
            }
            do {
                let prefix = fixtureExport ? "native" : "live"
                let output = directory.appendingPathComponent("\(prefix)-\(screen.rawValue.lowercased()).png")
                try data.write(to: output)
                print(output.path)
            } catch { fail("Native view export failed: \(error.localizedDescription)") }
            exportScreen(index + 1, state: state, directory: directory)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Native preview export failed: \(message)\n".utf8))
        exit(1)
    }
}
