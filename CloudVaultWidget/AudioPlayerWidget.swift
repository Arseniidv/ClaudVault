//
//  AudioPlayerWidget.swift
//  CloudVaultWidget
//
//  Интерактивный виджет аудиоплеера CloudVault.
//  Читает безопасный снимок `AudioPlayerSnapshot` из App Group
//  (без URL и токенов) и управляет воспроизведением через
//  AppIntents → AudioCommandBus → AudioPlayerService
//  в процессе приложения. Отдельный AVPlayer здесь не создаётся.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct AudioTimelineEntry: TimelineEntry {
    let date: Date
    /// nil — плеер ничего не воспроизводит.
    let snapshot: AudioPlayerSnapshot?
}

/// Виджет не опрашивает сеть и не хранит состояние: приложение
/// пишет снимок в App Group и вызывает
/// `WidgetCenter.reloadTimelines(ofKind:)` при каждом
/// значимом изменении (трек, play/pause, shuffle, repeat).
/// Политика `.never` — обновление только по запросу приложения.
struct AudioTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> AudioTimelineEntry {
        AudioTimelineEntry(date: Date(), snapshot: Self.mockSnapshot)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (AudioTimelineEntry) -> Void
    ) {
        completion(
            AudioTimelineEntry(
                date: Date(),
                snapshot: loadSharedSnapshot() ?? Self.mockSnapshot
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<AudioTimelineEntry>) -> Void
    ) {
        let entry = AudioTimelineEntry(
            date: Date(),
            snapshot: loadSharedSnapshot()
        )
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadSharedSnapshot() -> AudioPlayerSnapshot? {
        guard let defaults = UserDefaults(
            suiteName: WidgetStorage.appGroupID
        ), let data = defaults.data(
            forKey: AudioWidgetConfig.snapshotKey
        ) else { return nil }
        return try? JSONDecoder().decode(AudioPlayerSnapshot.self, from: data)
    }

    private static let mockSnapshot = AudioPlayerSnapshot(
        track: WidgetAudioTrack(
            id: "preview",
            title: "Demo Track",
            artist: "Artist",
            album: nil,
            providerName: "googleDrive",
            fileName: "demo.mp3",
            duration: 214,
            position: 34,
            isPlaying: true,
            isLoading: false,
            repeatMode: "all",
            shuffleEnabled: false,
            artworkFileName: nil,
            queueIndex: 1,
            queueCount: 3,
            hasNext: true,
            hasPrevious: false,
            updatedAt: Date()
        ),
        volume: 1,
        errorMessage: nil,
        updatedAt: Date()
    )
}

// MARK: - Widget

struct AudioPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AudioWidgetConfig.widgetKind,
            provider: AudioTimelineProvider()
        ) { entry in
            AudioPlayerWidgetEntryView(entry: entry)
                .containerBackground(
                    Color(red: 0.055, green: 0.067, blue: 0.090),
                    for: .widget
                )
        }
        .configurationDisplayName("ClaudVault Плеер")
        .description("Управление воспроизведением аудио из облака.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge
        ])
    }
}

// MARK: - Entry View

struct AudioPlayerWidgetEntryView: View {
    var entry: AudioTimelineProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let track = entry.snapshot?.track {
            switch family {
            case .systemSmall:
                SmallPlayerView(entry: entry, track: track)
            case .systemMedium:
                MediumPlayerView(entry: entry, track: track)
            case .systemLarge, .systemExtraLarge:
                LargePlayerView(entry: entry, track: track)
            default:
                SmallPlayerView(entry: entry, track: track)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundStyle(.pink.opacity(0.8))
            Text("Ничего не играет")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Откройте аудиофайл в ClaudVault")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://player"))
    }
}

// MARK: - Helpers

enum AudioWidgetStyle {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let surface = Color(red: 0.090, green: 0.105, blue: 0.140)
    static let accent = Color(red: 0.25, green: 0.48, blue: 1.00)

    /// Позиция на момент отрисовки entry: снимок хранит
    /// позицию на `updatedAt`, для играющего трека
    /// доматываем прошедшее время.
    static func displayPosition(
        _ track: WidgetAudioTrack,
        at date: Date
    ) -> TimeInterval {
        var position = track.position
        if track.isPlaying {
            position += max(0, date.timeIntervalSince(track.updatedAt))
        }
        if track.duration > 0 {
            position = min(position, track.duration)
        }
        return position
    }

    static func progressFraction(
        _ track: WidgetAudioTrack,
        at date: Date
    ) -> Double {
        guard track.duration > 0 else { return 0 }
        return min(
            max(displayPosition(track, at: date) / track.duration, 0),
            1
        )
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(
                format: "%d:%02d:%02d",
                total / 3600,
                (total % 3600) / 60,
                total % 60
            )
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    static func artwork(_ track: WidgetAudioTrack, size: CGFloat) -> some View {
        if let image = AudioArtworkStore.image(
            fileName: track.artworkFileName
        ) {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.4),
                        accent.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// Кнопка play/pause с AppIntent — реальная команда
    /// в приложение, а не просто открытие.
    static func playPauseButton(isPlaying: Bool) -> some View {
        Button(intent: AudioTogglePlayPauseIntent()) {
            Image(
                systemName: isPlaying ? "pause.fill" : "play.fill"
            )
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(accent)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    static func sideButton(
        systemImage: String,
        intent: some AppIntent
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small

private struct SmallPlayerView: View {
    let entry: AudioTimelineProvider.Entry
    let track: WidgetAudioTrack

    var body: some View {
        VStack(spacing: 8) {
            AudioWidgetStyle.artwork(track, size: 56)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let artist = track.artist {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            AudioWidgetStyle.playPauseButton(
                isPlaying: track.isPlaying
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://player"))
    }
}

// MARK: - Medium

private struct MediumPlayerView: View {
    let entry: AudioTimelineProvider.Entry
    let track: WidgetAudioTrack

    var body: some View {
        HStack(spacing: 14) {
            AudioWidgetStyle.artwork(track, size: 64)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist ?? track.providerName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                VStack(spacing: 4) {
                    ProgressView(
                        value: AudioWidgetStyle.progressFraction(
                            track, at: entry.date
                        )
                    )
                    .progressViewStyle(.linear)
                    .tint(AudioWidgetStyle.accent)

                    HStack {
                        Text(AudioWidgetStyle.formatTime(
                            AudioWidgetStyle.displayPosition(
                                track, at: entry.date
                            )
                        ))
                        Spacer()
                        Text(AudioWidgetStyle.formatTime(track.duration))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                AudioWidgetStyle.sideButton(
                    systemImage: "backward.fill",
                    intent: AudioPreviousTrackIntent()
                )
                AudioWidgetStyle.playPauseButton(
                    isPlaying: track.isPlaying
                )
                AudioWidgetStyle.sideButton(
                    systemImage: "forward.fill",
                    intent: AudioNextTrackIntent()
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://player"))
    }
}

// MARK: - Large

private struct LargePlayerView: View {
    let entry: AudioTimelineProvider.Entry
    let track: WidgetAudioTrack

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(track.fileName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                Spacer()
                Text("\(track.queueIndex) / \(track.queueCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            AudioWidgetStyle.artwork(track, size: 140)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 3) {
                Text(track.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(track.artist ?? track.providerName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            VStack(spacing: 5) {
                ProgressView(
                    value: AudioWidgetStyle.progressFraction(
                        track, at: entry.date
                    )
                )
                .progressViewStyle(.linear)
                .tint(AudioWidgetStyle.accent)

                HStack {
                    Text(AudioWidgetStyle.formatTime(
                        AudioWidgetStyle.displayPosition(
                            track, at: entry.date
                        )
                    ))
                    Spacer()
                    Text(AudioWidgetStyle.formatTime(track.duration))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)

            HStack(spacing: 26) {
                AudioWidgetStyle.sideButton(
                    systemImage: "backward.fill",
                    intent: AudioPreviousTrackIntent()
                )
                AudioWidgetStyle.playPauseButton(
                    isPlaying: track.isPlaying
                )
                .scaleEffect(1.25)
                AudioWidgetStyle.sideButton(
                    systemImage: "forward.fill",
                    intent: AudioNextTrackIntent()
                )
            }

            HStack(spacing: 24) {
                AudioWidgetStyle.sideButton(
                    systemImage: track.shuffleEnabled
                        ? "shuffle" : "shuffle",
                    intent: AudioToggleShuffleIntent()
                )
                .opacity(track.shuffleEnabled ? 1 : 0.45)

                AudioWidgetStyle.sideButton(
                    systemImage: track.repeatMode == "one"
                        ? "repeat.1" : "repeat",
                    intent: AudioCycleRepeatIntent()
                )
                .opacity(track.repeatMode == "off" ? 0.45 : 1)

                Spacer()

                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://player"))
    }
}

#Preview(as: .systemMedium) {
    AudioPlayerWidget()
} timeline: {
    AudioTimelineEntry(
        date: .now,
        snapshot: AudioPlayerSnapshot(
            track: WidgetAudioTrack(
                id: "preview",
                title: "Demo Track",
                artist: "Artist",
                album: "Album",
                providerName: "googleDrive",
                fileName: "demo.mp3",
                duration: 214,
                position: 34,
                isPlaying: true,
                isLoading: false,
                repeatMode: "all",
                shuffleEnabled: false,
                artworkFileName: nil,
                queueIndex: 1,
                queueCount: 3,
                hasNext: true,
                hasPrevious: false,
                updatedAt: Date()
            ),
            volume: 1,
            errorMessage: nil,
            updatedAt: Date()
        )
    )
}
