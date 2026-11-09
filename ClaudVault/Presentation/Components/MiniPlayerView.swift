import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Мини-плеер внизу главного окна: виден, пока в очереди
/// есть текущий трек. Тап по названию открывает полноэкранный
/// плеер, кнопки управляют `AudioPlayerService` напрямую —
/// тем же AVPlayer, что и в полном плеере, виджете
/// и Live Activity.
struct MiniPlayerView: View {
    let service: AudioPlayerService
    let onTap: () -> Void

    var body: some View {
        if let track = service.currentTrack {
            VStack(spacing: 0) {
                // Тонкий индикатор прогресса.
                GeometryReader { geo in
                    let fraction = service.duration > 0
                        ? min(max(service.position / service.duration, 0), 1)
                        : 0
                    Rectangle()
                        .fill(AppColors.accent)
                        .frame(
                            width: geo.size.width * CGFloat(fraction),
                            height: 2
                        )
                }
                .frame(height: 2)

                HStack(spacing: 8) {
                    // Тап по информации — полноэкранный плеер.
                    Button(action: onTap) {
                        HStack(spacing: 12) {
                            artwork(track: track)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(track.artist ?? track.provider.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        service.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        service.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 34, height: 34)
                            Image(
                                systemName: service.isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.onAccent)
                            .offset(x: service.isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        service.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColors.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func artwork(track: AudioTrack) -> some View {
        if let data = track.artworkJPEG,
           let image = Self.image(from: data) {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                AppColors.surfaceSecondary
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.accent)
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
}
