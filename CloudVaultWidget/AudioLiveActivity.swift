//
//  AudioLiveActivity.swift
//  CloudVaultWidget
//
//  Live Activity «сейчас играет»: экран блокировки iPhone
//  и Dynamic Island (compact / minimal / expanded).
//  Состояние обновляет приложение через ActivityKit,
//  кнопки управляют плеером через AppIntents → AudioCommandBus.
//

import WidgetKit
import SwiftUI
import AppIntents
#if os(iOS) && canImport(ActivityKit)
import ActivityKit

private enum AudioLiveActivityPalette {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let accent = Color(red: 0.25, green: 0.48, blue: 1.00)
}

struct AudioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: AudioLiveActivityAttributes.self
        ) { context in
            // MARK: Lock Screen / баннер
            AudioLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded
                DynamicIslandExpandedRegion(.leading) {
                    artworkView(context: context, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AudioLiveActivityPalette.accent)
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let artist = context.state.artist {
                            Text(artist)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        progressRow(context: context)
                        HStack(spacing: 20) {
                            transportButton(
                                systemImage: "backward.fill",
                                intent: AudioPreviousTrackIntent()
                            )
                            transportButton(
                                systemImage: context.state.isPlaying
                                    ? "pause.fill" : "play.fill",
                                intent: AudioTogglePlayPauseIntent()
                            )
                            .frame(width: 40, height: 40)
                            transportButton(
                                systemImage: "forward.fill",
                                intent: AudioNextTrackIntent()
                            )
                        }
                    }
                }
            } compactLeading: {
                // MARK: Compact leading — обложка/иконка
                artworkView(context: context, size: 22, compact: true)
            } compactTrailing: {
                // MARK: Compact trailing — состояние play/pause
                Image(
                    systemName: context.state.isPlaying
                        ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            } minimal: {
                // MARK: Minimal — иконка CloudVault
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AudioLiveActivityPalette.accent)
            }
            .keylineTint(AudioLiveActivityPalette.accent)
        }
    }

    /// Обложка из App Group контейнера; при отсутствии —
    /// градиентная заглушка с иконкой заметки.
    @ViewBuilder
    private func artworkView(
        context: ActivityViewContext<AudioLiveActivityAttributes>,
        size: CGFloat,
        compact: Bool = false
    ) -> some View {
        if let image = AudioArtworkStore.image(
            fileName: context.state.artworkFileName
        ) {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.4),
                        AudioLiveActivityPalette.accent.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: compact ? 10 : size * 0.4))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func progressRow(
        context: ActivityViewContext<AudioLiveActivityAttributes>
    ) -> some View {
        let duration = context.state.duration
        let fraction = duration > 0
            ? min(max(context.state.position / duration, 0), 1)
            : 0

        VStack(spacing: 4) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(AudioLiveActivityPalette.accent)
            HStack {
                Text(AudioWidgetStyle.formatTime(context.state.position))
                Spacer()
                Text(AudioWidgetStyle.formatTime(duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func transportButton(
        systemImage: String,
        intent: some AppIntent
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock Screen

private struct AudioLockScreenView: View {
    let context: ActivityViewContext<AudioLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Обложка
            Group {
                if let image = AudioArtworkStore.image(
                    fileName: context.state.artworkFileName
                ) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.pink.opacity(0.4),
                                AudioLiveActivityPalette.accent
                                    .opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = context.state.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                // Прогресс + время
                let duration = context.state.duration
                let fraction = duration > 0
                    ? min(max(context.state.position / duration, 0), 1)
                    : 0

                VStack(spacing: 3) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(AudioLiveActivityPalette.accent)
                    HStack {
                        Text(AudioWidgetStyle.formatTime(
                            context.state.position
                        ))
                        Spacer()
                        Text(AudioWidgetStyle.formatTime(duration))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 8)

            // Управление: prev / play-pause / next
            HStack(spacing: 10) {
                Button(intent: AudioPreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(intent: AudioTogglePlayPauseIntent()) {
                    Image(
                        systemName: context.state.isPlaying
                            ? "pause.fill" : "play.fill"
                    )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(intent: AudioNextTrackIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .activityBackgroundTint(AudioLiveActivityPalette.background)
        .activitySystemActionForegroundColor(.white)
    }
}
#endif
