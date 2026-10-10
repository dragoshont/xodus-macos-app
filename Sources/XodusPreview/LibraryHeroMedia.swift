// SPDX-License-Identifier: GPL-3.0-only
import AVKit
import SwiftUI

enum HeroMotionPolicy {
    static func permitsPlayback(allowed: Bool, enabled: Bool, reduceMotion: Bool,
                                lowPower: Bool, active: Bool, visible: Bool,
                                hasTrailer: Bool, supportsViewportVisibility: Bool = true) -> Bool {
        allowed && enabled && !reduceMotion && !lowPower && active && visible && hasTrailer
            && supportsViewportVisibility
    }
}

@MainActor
private final class HeroMediaPresentation: ObservableObject {
    @Published var visible = false
    @Published var paused = false
    @Published var hovered = false
    @Published var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
}

private struct HeroAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

struct LibraryHeroMedia<Poster: View>: View {
    let trailer: CatalogTrailer?
    var allowsPlayback = true
    @ViewBuilder let poster: () -> Poster
    @AppStorage("Xodus.heroAnimationsEnabled") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation = HeroMediaPresentation()
    @StateObject private var playback = CatalogTrailerPlayback()

    private var supportsViewportVisibility: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    private var eligible: Bool {
        HeroMotionPolicy.permitsPlayback(allowed: allowsPlayback, enabled: enabled,
            reduceMotion: reduceMotion, lowPower: presentation.lowPower, active: scenePhase == .active,
            visible: presentation.visible, hasTrailer: trailer != nil,
            supportsViewportVisibility: supportsViewportVisibility)
            && presentation.hovered
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            poster()
            if let player = playback.player, playback.error == nil {
                HeroAVPlayerView(player: player)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if eligible {
                Button {
                    if playback.error != nil, let trailer {
                        playback.play(trailer, muted: true, loops: true, preview: true)
                    } else { presentation.paused.toggle() }
                } label: {
                    Image(systemName: playback.error != nil ? "arrow.clockwise"
                          : presentation.paused ? "play.fill" : "pause.fill")
                }
                .modifier(LibraryActionStyle(primary: false)).buttonBorderShape(.circle)
                .accessibilityLabel(playback.error != nil ? "Retry animated artwork"
                                    : presentation.paused ? "Resume animated artwork" : "Pause animated artwork")
                .help(playback.error ?? "Muted animated artwork. Game playback is a separate action.")
                .padding(.trailing, 24).padding(.top, 68)
            }
        }
        .onAppear { presentation.visible = true }
        .onHover { presentation.hovered = $0 }
        .modifier(HeroScrollVisibility { presentation.visible = $0 })
        .task(id: "\(eligible):\(presentation.paused):\(trailer?.id ?? "")") {
            if eligible, let trailer {
                if presentation.paused { playback.pause() }
                else if playback.player != nil { playback.resume() }
                else { playback.play(trailer, muted: true, loops: true, preview: true) }
            } else { playback.stop() }
        }
        .onChange(of: trailer?.id) { _, _ in playback.stop(); presentation.paused = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            presentation.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear { presentation.visible = false; playback.stop() }
    }
}

struct HeroScrollVisibility: ViewModifier {
    let changed: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollVisibilityChange(threshold: 0.1, changed)
        } else {
            content.onDisappear { changed(false) }
        }
    }
}
