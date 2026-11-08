import SwiftUI

/// Встроенный аудиоплеер для предпросмотра MP3/M4A/AAC.
///
/// Не создаёт собственный AVPlayer: при открытии регистрирует
/// трек в `AudioPlayerService` (единый плеер приложения) и
/// отображает его состояние. Закрытие предпросмотра НЕ
/// останавливает воспроизведение — музыка продолжает играть
/// в фоне, мини-плеере и на виджете.
struct AudioPreviewView: View {
    let item: FilePreviewItem
    /// Готовый потоковый дескриптор, если провайдер его отдал.
    /// nil — трек резолвится через `AudioSourceResolver`
    /// (кэш → стриминг → скачивание в кэш).
    var stream: CloudMediaStream? = nil

    @State private var didStartPlayback = false

    private var service: AudioPlayerService { .shared }

    private var file: CloudFile { item.file }
    private var provider: StorageProviderType { item.provider }

    /// Идентификатор трека в сервисе — совпадает с
    /// `AudioTrack.id` для облачного файла.
    private var trackID: String {
        "\(provider.rawValue)|\(file.id)"
    }

    /// Сервис играет именно этот трек — показываем live-состояние.
    private var isCurrentTrack: Bool {
        service.currentTrack?.id == trackID
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.pink.opacity(0.3),
                                AppColors.accent.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)

                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)
            }

            VStack(spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(provider.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isCurrentTrack ? service.position : 0 },
                        set: { service.seek(to: $0) }
                    ),
                    in: 0...max(displayDuration, 1)
                )
                .tint(.pink)
                .disabled(displayDuration <= 0 || !isCurrentTrack)

                HStack {
                    Text(AudioPlayerViewModel.formatTime(
                        isCurrentTrack ? service.position : 0
                    ))
                    Spacer()
                    Text(AudioPlayerViewModel.formatTime(displayDuration))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            HStack(spacing: 32) {
                Button {
                    service.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!service.hasPreviousTrack)

                Button {
                    service.togglePlayPause()
                } label: {
                    Image(
                        systemName: isCurrentTrack && service.isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
                .disabled(service.currentTrack == nil)

                Button {
                    service.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!service.hasNextTrack)
            }

            if let error = service.errorMessage, isCurrentTrack {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .padding(.bottom, 32)
        .background(Color(red: 0.035, green: 0.045, blue: 0.075).ignoresSafeArea())
        .onAppear(perform: startPlaybackIfNeeded)
    }

    /// Название: метаданные трека из сервиса, если уже
    /// распарсились, иначе имя файла без расширения.
    private var displayTitle: String {
        if isCurrentTrack, let title = service.currentTrack?.title {
            return title
        }
        let stem = file.name
            .split(separator: ".")
            .dropLast()
            .joined(separator: ".")
        return stem.isEmpty ? file.name : stem
    }

    private var displayDuration: TimeInterval {
        if isCurrentTrack, service.duration > 0 {
            return service.duration
        }
        return file.duration ?? 0
    }

    /// Регистрирует трек в едином плеере и запускает
    /// воспроизведение. Повторный onAppear (возврат из
    /// другого preview) не перезапускает трек.
    private func startPlaybackIfNeeded() {
        guard !didStartPlayback else { return }
        didStartPlayback = true

        // Если этот же трек уже играет — ничего не делаем.
        if service.currentTrack?.id == trackID { return }

        let track = AudioTrack(
            file: file,
            provider: provider,
            stream: stream
        )
        service.play(track: track)
    }
}
