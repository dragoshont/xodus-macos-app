// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
enum PreviewWindow {
    static func configure() {
        for window in NSApp.windows where window.title == "Xodus" || window.title.contains("Fixture Preview") {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .hidden
            window.styleMask.remove(.fullSizeContentView)
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
        }
    }
}
