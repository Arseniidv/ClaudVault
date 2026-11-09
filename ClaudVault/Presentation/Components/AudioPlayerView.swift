import SwiftUI
import ClaudVaultDomain
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Полноэкранный аудиоплеер CloudVault.
///
/// Управляет `AudioPlayerService` — единым AVPlayer
/// приложения: состояние, обложка, прогресс, громкость,
/// shuffle/repeat синхронизированы с мини-плеером,
/// виджетом, Live Activity и системными командами.
struct AudioPlayerView: View {
    @State private var viewModel: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(service: AudioPlayerService? = nil) {
        _viewModel = State(
            initialValue: AudioPlayerViewModel(service: service)
        )
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if let track = viewModel.track {
                playerContent(track: track)
            } else {
                emptyState
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Content

    private func playerContent(track: AudioTrack) -> some View {
        VStack(spacing: 20) {
            // Заголовок + закрытие
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            artworkView(track: track)

            VStack(spacing: 4) {
                Text(track.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(viewModel.subtitleText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)

                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24)

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            progressSection

            controlsSection

            volumeSection

            footerInfo(track: track)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(track: AudioTrack) -> some View {
        Group {
            if let data = track.artworkJPEG,
               let image = Self.image(from: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.pink.opacity(0.35),
                            AppColors.accent.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .overlay {
            if viewModel.isLoading {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.35))
                    .overlay {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .scaleEffect(1.4)
                    }
            }
        }
    }

    private static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    // MARK: - Sections

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: viewModel.positionBinding,
                in: 0...max(viewModel.duration, 1)
            )
            .tint(AppColors.accent)
            .disabled(viewModel.duration <= 0)

            HStack {
                Text(AudioPlayerViewModel.formatTime(viewModel.position))
                Spacer()
                Text(AudioPlayerViewModel.formatTime(viewModel.duration))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(AppColors.textMuted)
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        viewModel.shuffleEnabled
                            ? AppColors.accent
                            : AppColors.textMuted
                    )
            }
            .buttonStyle(.plain)

            Button {
                viewModel.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasPreviousTrack)

            Button {
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 68, height: 68)
                    Image(
                        systemName: viewModel.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .offset(x: viewModel.isPlaying ? 0 : 3)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.track == nil)

            Button {
                viewModel.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasNextTrack)

            Button {
                viewModel.cycleRepeat()
            } label: {
                Image(systemName: viewModel.repeatMode.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        viewModel.repeatMode == .off
                            ? AppColors.textMuted
                            : AppColors.accent
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var volumeSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)

            Slider(value: viewModel.volumeBinding, in: 0...1)
                .tint(AppColors.accent)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
        }
    }

    private func footerInfo(track: AudioTrack) -> some View {
        HStack {
            Label(
                track.provider.name,
                systemImage: track.provider.icon
            )
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)

            Spacer()

            if let queue = viewModel.queuePositionText {
                Text("Трек \(queue)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textMuted)
            Text("Ничего не воспроизводится")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Button("Закрыть") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.onAccent)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
