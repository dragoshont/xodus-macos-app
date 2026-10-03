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

struct FloatingNavigation: View {
    @EnvironmentObject private var state: AppState

    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(Destination.allCases) { destination in
                Button { state.navigate(destination) } label: {
                    Text(destination.rawValue)
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background {
                            if state.destination == destination {
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(destination.rawValue)
                .accessibilityIdentifier("xodus.navigation.\(destination.rawValue.lowercased())")
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(state.destination == destination ? .isSelected : [])
                .accessibilityAction { state.navigate(destination) }
            }
        }

        .padding(6)
        .modifier(NativeGlass())
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 12) { navigation }
        } else {
            navigation
        }
    }

}

struct FloatingAccount: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        Button { state.showingWelcome = true } label: {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .frame(width: 48, height: 48)
                .modifier(NativeGlass())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fixture account")
    }
}
