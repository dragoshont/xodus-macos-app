// SPDX-License-Identifier: GPL-3.0-only
import AVKit
import Combine
import SwiftUI

struct CatalogAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
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

@MainActor
final class CatalogTrailerPlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    private var observation: AnyCancellable?
    private var endObservation: AnyCancellable?

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func play(_ trailer: CatalogTrailer, muted: Bool = false, loops: Bool = false) {
        stop()
        let asset = AVURLAsset(url: trailer.url, options: [AVURLAssetHTTPCookiesKey: []])
        let item = AVPlayerItem(asset: asset)
        if muted {
            item.preferredPeakBitRate = 1_500_000
            item.preferredForwardBufferDuration = 5
        }
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        observation = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
            if status == .failed {
                self?.player?.pause()
                self?.error = "The trailer couldn't be played. Try again or view the screenshots."
            }
        }
        if loops {
            endObservation = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in
                    guard let player = self?.player, player.currentItem === item else { return }
                    player.seek(to: .zero)
                    player.play()
                }
        }
        self.player = player
        player.play()
    }

    func stop() {
        observation = nil
        endObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        error = nil
    }
}

struct CatalogTrailerView: View {
    let trailer: CatalogTrailer
    var allowsLoading = true
    var allowsPlayback = true
    @StateObject private var playback = CatalogTrailerPlayback()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player = playback.player {
                CatalogAVPlayerView(player: player).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(trailer.caption)
                HStack {
                    Text(trailer.caption).font(.headline)
                    Spacer()
                    Button("Close trailer", systemImage: "xmark", action: playback.stop)
                }
                if let error = playback.error {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    Button("Try Again") { playback.play(trailer) }.disabled(!allowsPlayback)
                }
            } else {
                Button { playback.play(trailer) } label: {
                    ZStack {
                        CatalogArtworkView(reference: allowsLoading ? trailer.preview : nil,
                                           status: trailer.preview == nil ? .absent : .available)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        Label("Play \(trailer.caption)", systemImage: "play.fill")
                            .font(.headline).padding(14).modifier(NativeToolbarMaterial())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).disabled(!allowsPlayback)
                .accessibilityLabel("Play \(trailer.caption). Streams video.")
            }
        }
        .onDisappear(perform: playback.stop)
    }
}
