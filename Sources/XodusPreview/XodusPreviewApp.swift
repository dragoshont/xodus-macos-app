// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XodusCore

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { PreviewWindow.configure() }
    }
}

@main
struct XodusPreviewApp: App {
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var delegate
    @StateObject private var state = AppState()

    init() {
        if CommandLine.arguments.contains("--self-check") {
            exit(PreviewChecks.run() ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("Xodus - Fixture Preview") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Navigate") {
                Button("Library") { state.navigate(.library) }.keyboardShortcut("1")
                Button("Discover") { state.navigate(.discover) }.keyboardShortcut("2")
                Button("Downloads") { state.navigate(.downloads) }.keyboardShortcut("3")
            }
        }
        Settings {
            PreviewSettings()
                .environmentObject(state)
                .frame(width: 510)
        }
    }
}
