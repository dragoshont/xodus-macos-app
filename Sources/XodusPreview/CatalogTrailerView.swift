// SPDX-License-Identifier: GPL-3.0-only
import AVKit
import Combine
import SwiftUI

@MainActor
final class CatalogTrailerPlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    private var observation: AnyCancellable?

    func play(_ trailer: CatalogTrailer) {
        stop()
        let asset = AVURLAsset(url: trailer.url, options: [AVURLAssetHTTPCookiesKey: []])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        observation = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
            if status == .failed { self?.error = "The trailer couldn't be played. Try again or view the screenshots." }
        }
        self.player = player
        player.play()
    }

    func stop() {
        observation = nil
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
                VideoPlayer(player: player).aspectRatio(16.0 / 9.0, contentMode: .fit)
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
