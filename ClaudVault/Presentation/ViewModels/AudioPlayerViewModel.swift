import Foundation
import Observation
import SwiftUI
import ClaudVaultDomain

/// View-model полноэкранного аудиоплеера.
///
/// Тонкая обёртка над `AudioPlayerService`: сам сервис —
/// `@Observable` singleton с единственным `AVPlayer`,
/// VM лишь предоставляет форматирование и binding'и
/// для SwiftUI-контролов.
@MainActor
@Observable
final class AudioPlayerViewModel {

    let service: AudioPlayerService

    init(service: AudioPlayerService? = nil) {
        self.service = service ?? .shared
    }

    var track: AudioTrack? { service.currentTrack }
    var isPlaying: Bool { service.isPlaying }
    var isLoading: Bool { service.isLoading || service.isBuffering }
    var position: TimeInterval { service.position }
    var duration: TimeInterval { service.duration }
    var volume: Float { service.volume }
    var repeatMode: AudioRepeatMode { service.repeatMode }
    var shuffleEnabled: Bool { service.shuffleEnabled }
    var errorMessage: String? { service.errorMessage }
    var hasNextTrack: Bool { service.hasNextTrack }
    var hasPreviousTrack: Bool { service.hasPreviousTrack }

    /// 0...1 для ProgressView/Slider.
    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Binding для слайдера позиции: get — текущая позиция,
    /// set — seek в секундах.
    var positionBinding: Binding<TimeInterval> {
        Binding(
            get: { self.position },
            set: { self.service.seek(to: $0) }
        )
    }

    var volumeBinding: Binding<Float> {
        Binding(
            get: { self.volume },
            set: { self.service.setVolume($0) }
        )
    }

    /// "3 / 12" — позиция в очереди.
    var queuePositionText: String? {
        guard let index = service.currentIndex else { return nil }
        return "\(index + 1) / \(service.queue.count)"
    }

    /// Подпись под названием: артист → провайдер → имя файла.
    var subtitleText: String {
        if let artist = track?.artist, !artist.isEmpty {
            return artist
        }
        return track?.provider.name ?? ""
    }

    func togglePlayPause() { service.togglePlayPause() }
    func next() { service.next() }
    func previous() { service.previous() }
    func toggleShuffle() { service.toggleShuffle() }
    func cycleRepeat() { service.cycleRepeatMode() }
    func skipForward() { service.skip(by: 10) }
    func skipBackward() { service.skip(by: -10) }

    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
