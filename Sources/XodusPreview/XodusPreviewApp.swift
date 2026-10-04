// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XodusCore

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var liveSession: LiveSession?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { PreviewWindow.configure() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let liveSession else { return .terminateNow }
        Task {
            let closed = await liveSession.disconnect()
            sender.reply(toApplicationShouldTerminate: closed)
        }
        return .terminateLater
    }
}

@main
struct XodusPreviewApp: App {
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @StateObject private var session = LiveSession()

    init() {
        if CommandLine.arguments.contains("--live-check") { NativeChecks.launch() }
        if CommandLine.arguments.contains("--self-check") {
            exit(PreviewChecks.run() ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup(state.fixtureMode ? "Xodus - Fixture Preview" : "Xodus") {
            Group {
                if state.fixtureMode { RootView() }
                else { LiveRootView() }
            }
                .environmentObject(state)
                .environmentObject(session)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear { delegate.liveSession = session }
        }
        .defaultSize(width: 1200, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Navigate") {
                Button("Library") { state.navigate(.library) }.keyboardShortcut("1")
                Button("Discover") { state.navigate(.discover) }.keyboardShortcut("2")
                Button("Downloads") { state.navigate(.downloads) }.keyboardShortcut("3")
            }
            CommandMenu("Xodus") {
                Button("Account") { state.showingAccount = true }
                    .disabled(state.fixtureMode)
                Button("Return to live Xodus") {
                    state.fixtureMode = false
                    state.navigate(.library)
                }.disabled(!state.fixtureMode)
            }
        }
        Settings {
            Group {
                if state.fixtureMode { PreviewSettings() }
                else { LiveSettingsView() }
            }
                .environmentObject(state)
                .environmentObject(session)
        }
    }
}
