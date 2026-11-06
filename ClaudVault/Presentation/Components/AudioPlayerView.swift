import SwiftUI
import AVFoundation

/// Плеер для потокового воспроизведения аудио из облака.
/// Файл не скачивается — AVPlayer читает его по прямой ссылке
/// (Dropbox temporary_link или Google Drive alt=media + Bearer).
struct AudioPlayerView: View {
    let file: CloudFile
    let providerName: String
    let stream: CloudMediaStream

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.pink)

            VStack(spacing: 6) {
                Text(file.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(providerName)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { seek(to: $0) }
                    ),
                    in: 0...max(duration, 1)
                )
                .tint(.pink)
                .disabled(duration <= 0)

                HStack {
                    Text(Self.formatTime(currentTime))
                    Spacer()
                    Text(Self.formatTime(duration))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)
            }
            .disabled(player == nil)

            Spacer()
        }
        .padding(.bottom, 32)
        .background(Color(red: 0.035, green: 0.045, blue: 0.075).ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: teardownPlayer)
    }

    private func setupPlayer() {
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": stream.headers
        ]
        let asset = AVURLAsset(url: stream.url, options: options)
        let item = AVPlayerItem(asset: asset)

        Task {
            if let loadedDuration = try? await asset.load(.duration) {
                let seconds = loadedDuration.seconds
                if seconds.isFinite, seconds > 0 {
                    duration = seconds
                }
            }
        }

        let player = AVPlayer(playerItem: item)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTime = time.seconds
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            currentTime = 0
            player.seek(to: .zero)
        }

        player.play()
        isPlaying = true
    }

    private func teardownPlayer() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
