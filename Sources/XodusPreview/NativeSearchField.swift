// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Keep the native field editor and an explicit readable placeholder over immersive artwork.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    var enabled = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusedSearchField {
        let view = FocusedSearchField()
        view.delegate = context.coordinator
        view.isBezeled = false
        view.isBordered = false
        view.drawsBackground = false
        view.focusRingType = .exterior
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textColor = .white
        view.setAccessibilityIdentifier("xodus.catalog.search")
        if let cell = view.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.sendsSearchStringImmediately = true
        view.sendsWholeSearchString = false
        return view
    }

    func updateNSView(_ view: FocusedSearchField, context: Context) {
        context.coordinator.parent = self
        view.wantsFocus = focused
        view.isEnabled = enabled
        if view.stringValue != text { view.stringValue = text }
        view.placeholderAttributedString = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(enabled ? 0.88 : 0.68),
                         .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        view.setAccessibilityLabel(placeholder)
        if focused, enabled, view.currentEditor() == nil {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.wantsFocus, view.isEnabled else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
    }
}

final class FocusedSearchField: NSSearchField {
    var wantsFocus = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus, isEnabled { window?.makeFirstResponder(self) }
    }
}
