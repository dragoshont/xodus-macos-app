// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct NativeGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(scheme == .dark ? Color(white: 0.12) : Color(nsColor: .windowBackgroundColor),
                               in: Capsule())
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct GlassAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        if #available(macOS 26, *) {
            Button(title, action: action).buttonStyle(.glassProminent)
        } else {
            Button(title, action: action).buttonStyle(.borderedProminent)
        }
    }
}

struct XodusToolbar: ToolbarContent {
    let selection: Binding<Destination>
    let accountLabel: String
    let accountSymbol: String
    let openAccount: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Navigate Xodus", selection: selection) {
                ForEach(Destination.allCases) { destination in
                    Text(destination.rawValue).tag(destination)
                        .accessibilityIdentifier("xodus.navigation.\(destination.rawValue.lowercased())")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Navigate Xodus")
            .accessibilityIdentifier("xodus.navigation")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(accountLabel, systemImage: accountSymbol, action: openAccount)
                .labelStyle(.iconOnly)
                .help(accountLabel)
                .accessibilityIdentifier("xodus.account")
        }
    }
}
