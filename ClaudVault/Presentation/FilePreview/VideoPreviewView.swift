import SwiftUI
import AVFoundation
import ClaudVaultDomain
#if os(iOS)
import AVKit
#else
import AVKit
#endif

/// Встроенный видеоплеер для предпросмотра MP4/MOV.
/// Использует нативные контролы AVKit: воспроизведение/пауза,
/// перемотка, громкость, полноэкранный режим, длительность.
/// Плеер создаётся один раз и освобождается при закрытии.
struct VideoPreviewView: View {
    var stream: CloudMediaStream? = nil
    var localFileURL: URL? = nil

    @State private var player: AVPlayer?

    var body: some View {
        PlayerContainer(player: player)
            .background(Color.black)
            .onAppear(perform: setupPlayer)
            .onDisappear(perform: teardownPlayer)
    }

    private func makeAsset() -> AVURLAsset? {
        if let stream {
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": stream.headers
            ]
            return AVURLAsset(url: stream.url, options: options)
        }
        if let localFileURL {
            return AVURLAsset(url: localFileURL)
        }
        return nil
    }

    private func setupPlayer() {
        guard player == nil, let asset = makeAsset() else { return }
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
    }
}

// MARK: - Platform player container

#if os(iOS)

private struct PlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.player = player
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

#else

private struct PlayerContainer: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

#endif
