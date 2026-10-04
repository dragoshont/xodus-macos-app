// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

@MainActor
enum NativeUIChecks {
    static func run(check: (Bool, String) -> Void) {
        let application = NSApplication.shared
        let windows = application.windows.count
        check(NativeToolbarSearch.width(text: "", focused: false) == 32
              && NativeToolbarSearch.width(text: "", focused: true) == 220,
              "Grouped native toolbar search stays compact until native editing or Command-F focus")
        check(NativeToolbarSearch.width(text: "scoped query", focused: false) == 220,
              "A nonempty toolbar query retains the editor and native clear control after focus leaves")
        for (query, focus, width) in [("", false, CGFloat(32)), ("", true, CGFloat(220)),
                                      ("scoped query", false, CGFloat(220))] {
            let host = NSHostingView(rootView: NativeToolbarSearch(
                text: .constant(query), focused: .constant(focus), placeholder: "Search your Library"))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 36)
            host.layoutSubtreeIfNeeded()
            let fields = descendants(of: host).compactMap { $0 as? NSSearchField }
            check(host.window == nil && fields.count == 1
                  && fields.first.map { abs($0.bounds.width - width) < 1 && $0.window == nil } == true,
                  "Compact/expanded toolbar layout contains exactly one correctly sized detached native editor")
        }
        var text = "old scope"
        var focused = false
        var edits = 0
        var search = NativeSearchField(
            text: Binding(get: { text }, set: { text = $0; edits += 1 }),
            focused: Binding(get: { focused }, set: { focused = $0 }),
            placeholder: "Search your Library")
        let coordinator = search.makeCoordinator()
        let field = search.makeField(coordinator: coordinator)
        let cell = field.cell as? NSSearchFieldCell
        check(field.window == nil && field.stringValue == text
              && field.placeholderString == "Search your Library",
              "Shared native search initializes text and scope without a window")
        check(field.isBezeled && cell?.searchButtonCell != nil && cell?.cancelButtonCell != nil,
              "Shared search retains the stock bezel and one native search/cancel pair")
        let placeholderColor = field.placeholderAttributedString?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        check(field.textColor == .controlTextColor && placeholderColor != .white,
              "Search uses semantic control text and the system placeholder appearance")
        field.stringValue = "edited query"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        coordinator.searchChanged(field)
        check(text == "edited query" && edits == 1,
              "Native edit notification and search action commit the query only once")
        field.stringValue = ""
        _ = field.sendAction(field.action, to: field.target)
        check(text.isEmpty && edits == 2, "The native clear/search action updates the same scoped binding")
        text = "next scope"
        search = NativeSearchField(text: search.$text, focused: search.$focused,
                                   placeholder: "Search Microsoft Store games")
        search.updateField(field, coordinator: coordinator)
        check(field.stringValue == "next scope" && field.placeholderString == search.placeholder && edits == 2,
              "Scope/binding refresh neither duplicates edits nor retains an old placeholder")
        focused = true
        search.enabled = false
        search.updateField(field, coordinator: coordinator)
        field.stringValue = "disabled edit"
        coordinator.searchChanged(field)
        check(!field.isEnabled && !field.wantsFocus && text == "next scope",
              "Disabled scoped search neither edits its binding nor requests focus")
        search.enabled = true
        search.updateField(field, coordinator: coordinator)
        check(field.wantsFocus && field.window == nil && field.stringValue == text,
              "Command-F focus intent survives re-enabling without creating or activating a window")
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        search.updateField(field, coordinator: coordinator)
        check(!focused && !field.wantsFocus, "Ending native editing clears the shared focus intent")

        let layout = AccountActionsLayout()
        let horizontalBounds = CGRect(x: 0, y: 0, width: 610, height: 28)
        let horizontal = layout.frames(for: [CGSize(width: 90, height: 28),
                                             CGSize(width: 110, height: 28),
                                             CGSize(width: 170, height: 28)], in: horizontalBounds)
        check(horizontal.count == 3 && horizontal.allSatisfy { horizontalBounds.contains($0) }
              && horizontal.last?.maxX == horizontalBounds.maxX
              && zip(horizontal, horizontal.dropFirst()).allSatisfy { $0.0.maxX <= $0.1.minX },
              "Roomy account footer has one nonoverlapping frame per action and a trailing primary action")
        let compactBounds = CGRect(x: 0, y: 0, width: 440, height: 108)
        let longTitles = [CGSize(width: 230, height: 28), CGSize(width: 250, height: 28),
                          CGSize(width: 310, height: 28)]
        let stacked = layout.frames(for: longTitles, in: compactBounds)
        check(stacked.count == 3 && stacked.allSatisfy { compactBounds.contains($0) }
              && zip(stacked, stacked.dropFirst()).allSatisfy { $0.0.maxY <= $0.1.minY },
              "Long pending/cancel/status/sign-in labels stack without duplicated or hidden actions")
        let mirrored = AccountActionsLayout(layoutDirection: .rightToLeft)
            .frames(for: longTitles, in: compactBounds)
        check(mirrored.count == stacked.count && mirrored.allSatisfy { $0.minX == compactBounds.minX },
              "The adaptive account footer respects right-to-left action alignment")
        typealias Sheet = AccountSheetLayout<Color, Text, Text>
        check(Sheet.headerHeight(for: 340) == 0 && Sheet.headerHeight(for: 620) < 210
              && Sheet.headerHeight(for: 700) == 210,
              "Account decoration shrinks before the stable footer at constrained heights")
        for size in [CGSize(width: 480, height: 340), CGSize(width: 650, height: 620)] {
            let footer = NSView()
            let host = NSHostingView(rootView: AccountSheetLayout {
                Color.clear
            } content: {
                Text(String(repeating: "Synthetic pending or failure explanation. ", count: 80))
                    .fixedSize(horizontal: false, vertical: true)
            } actions: {
                AccountActionsLayout {
                    Button("Cancel sign-in") {}
                    Button("Check status") {}
                    Button("Sign in with Microsoft") {}.disabled(true)
                }
                .accessibilityIdentifier("synthetic.account.footer")
                .background(LayoutWitness(view: footer))
            })
            host.sizingOptions = []
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            check(host.window == nil && host.bounds.size == size && host.fittingSize.height <= 700,
                  "Long synthetic Account body lays out offscreen within the bounded sheet size")
            let footerFrame = footer.convert(footer.bounds, to: host)
            check(footer.superview != nil && footerFrame.width > 0 && footerFrame.height > 0
                  && host.bounds.contains(footerFrame)
                  && !ancestors(of: footer).contains(where: { $0 is NSScrollView }),
                  "The synthetic Account action footer stays inside the sheet and outside scrolling content")
        }
        check(application.windows.count == windows && field.window == nil,
              "Native control/layout checks create no window, provider or backend connection")
    }

    private static func ancestors(of view: NSView) -> [NSView] {
        guard let parent = view.superview else { return [] }
        return [parent] + ancestors(of: parent)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private struct LayoutWitness: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}
