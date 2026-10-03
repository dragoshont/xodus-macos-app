// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
enum PreviewWindow {
    static func configure() {
        for window in NSApp.windows where window.title == "Xodus" || window.title.contains("Fixture Preview") {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
        }
    }
}
