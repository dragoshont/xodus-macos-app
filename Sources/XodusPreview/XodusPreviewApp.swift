// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XodusCore

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var liveSession: LiveSession?
    var runtimeSettings: RuntimeProviderSettings?
    let termination = ApplicationTerminationCoordinator()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let closed = await termination.shutdown(session: liveSession, runtime: runtimeSettings)
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
#if XODUS_SHIPPING
        if !CommandLine.arguments.dropFirst().isEmpty {
            FileHandle.standardError.write(Data("This application does not accept preview, test or development arguments.\n".utf8))
            exit(64)
        }
#else
        if CommandLine.arguments.contains("--live-check") { NativeChecks.launch() }
        if CommandLine.arguments.contains("--self-check") {
            exit(PreviewChecks.run() ? 0 : 1)
        }
#endif
    }

    var body: some Scene {
        WindowGroup("Xodus") {
            Group {
#if !XODUS_SHIPPING
                if state.fixtureMode { RootView() }
                else { LiveRootView() }
#else
                LiveRootView()
#endif
            }
                .environmentObject(state)
                .environmentObject(session)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear {
                    delegate.liveSession = session
                    delegate.runtimeSettings = state.runtimeSettings
                }
        }
        .defaultSize(width: 1200, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Navigate") {
                Button("Library") { state.navigate(.library) }.keyboardShortcut("1")
                Button("Discover") { state.navigate(.discover) }.keyboardShortcut("2")
                Button("Downloads") { state.navigate(.downloads) }.keyboardShortcut("3")
            }
            CommandMenu("Xodus") {
#if !XODUS_SHIPPING
                Button("Account") { state.showingAccount = true }
                    .disabled(state.fixtureMode)
                Button("Return to live Xodus") {
                    state.fixtureMode = false
                    state.navigate(.library)
                }.disabled(!state.fixtureMode)
#else
                Button("Account") { state.showingAccount = true }
#endif
            }
        }
        Settings {
            Group {
#if !XODUS_SHIPPING
                if state.fixtureMode { PreviewSettings() }
                else { LiveSettingsView() }
#else
                LiveSettingsView()
#endif
            }
                .environmentObject(state)
                .environmentObject(session)
                .onAppear {
                    delegate.liveSession = session
                    delegate.runtimeSettings = state.runtimeSettings
                }
        }
    }
}
