import Foundation
import ClaudVaultDomain

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Управляет Live Activity «сейчас играет».
///
/// Активность — по одной на приложение (в отличие от
/// синхронизационных, которых может быть несколько).
/// Приложение — единственный источник правды: менеджер
/// читает состояние `AudioPlayerService` и обновляет
/// `ContentState`; виджет только рендерит.
///
/// Бюджет обновлений Live Activity ограничен, поэтому
/// прогресс обновляется не чаще `progressUpdateInterval`,
/// а смена трека/паузы — немедленно.
@MainActor
final class AudioLiveActivityManager {
    static let shared = AudioLiveActivityManager()

    private var activity: Activity<AudioLiveActivityAttributes>?

    /// Минимальный интервал между update-вызовами
    /// (кроме смены трека — те проходят всегда).
    private var lastUpdateAt = Date.distantPast
    private static let progressUpdateInterval: TimeInterval = 8

    /// Таймер догоняющих обновлений прогресса: Live Activity
    /// сама не тикает, поэтому пока трек играет, раз в
    /// `progressUpdateInterval` обновляем позицию.
    private var progressTimer: Timer?

    /// id трека, для которого активность уже создана —
    /// смена трека завершает старую активность и начинает новую.
    private var activeTrackID: String?

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {}

    /// Синхронизирует Live Activity с текущим состоянием
    /// плеера. Вызывается из `AudioPlayerService` при каждой
    /// публикации снимка; внутри — троттлинг.
    func sync(with service: AudioPlayerService) {
        guard areActivitiesEnabled else {
            endAll()
            return
        }

        guard let track = service.currentTrack,
              service.currentIndex != nil else {
            // Очередь пуста — живой активности нечего показывать.
            endAll()
            stopProgressTimer()
            return
        }

        let now = Date()
        let isSignificantChange = activeTrackID != track.id
            || lastContentState.isPlaying != service.isPlaying
            || lastContentState.title != track.title

        if activity == nil || isSignificantChange {
            startOrUpdate(
                service: service,
                track: track,
                force: true
            )
        } else if now.timeIntervalSince(lastUpdateAt)
                    >= Self.progressUpdateInterval {
            update(service: service, track: track)
        }

        // Пока играет — держим таймер для обновления прогресса.
        if service.isPlaying {
            startProgressTimer(service: service)
        } else {
            stopProgressTimer()
        }
    }

    /// Последний отправленный ContentState — для сравнения.
    private var lastContentState = AudioLiveActivityAttributes
        .ContentState(
            title: "",
            artist: nil,
            isPlaying: false,
            position: 0,
            duration: 0,
            artworkFileName: nil
        )

    private func contentState(
        for service: AudioPlayerService,
        track: AudioTrack
    ) -> AudioLiveActivityAttributes.ContentState {
        AudioLiveActivityAttributes.ContentState(
            title: track.title,
            artist: track.artist,
            isPlaying: service.isPlaying,
            position: service.position,
            duration: service.duration > 0
                ? service.duration
                : (track.knownDuration ?? 0),
            artworkFileName: service.artworkFileName
        )
    }

    private func startOrUpdate(
        service: AudioPlayerService,
        track: AudioTrack,
        force: Bool
    ) {
        let state = contentState(for: service, track: track)
        let attributes = AudioLiveActivityAttributes(
            trackID: track.id,
            providerName: track.provider.rawValue,
            fileName: track.fileName
        )

        if activeTrackID != track.id {
            // Смена трека: завершаем предыдущую активность
            // и создаём новую с актуальными attributes.
            Task { await activity?.end(nil, dismissalPolicy: .immediate) }
            activity = nil
            activeTrackID = track.id

            if let newActivity = try? Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            ) {
                activity = newActivity
            }
        } else if let activity {
            Task {
                await activity.update(
                    .init(state: state, staleDate: nil)
                )
            }
        }

        lastContentState = state
        lastUpdateAt = Date()
    }

    private func update(
        service: AudioPlayerService,
        track: AudioTrack
    ) {
        guard let activity else { return }
        let state = contentState(for: service, track: track)
        lastContentState = state
        lastUpdateAt = Date()
        Task {
            await activity.update(
                .init(state: state, staleDate: nil)
            )
        }
    }

    /// Завершает активность и чистит состояние.
    private func endAll() {
        activeTrackID = nil
        lastContentState = AudioLiveActivityAttributes
            .ContentState(
                title: "",
                artist: nil,
                isPlaying: false,
                position: 0,
                duration: 0,
                artworkFileName: nil
            )
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(
                nil,
                dismissalPolicy: .immediate
            )
        }
    }

    // MARK: - Progress timer

    /// Периодическое обновление позиции, пока трек играет.
    /// `Timer` на main run loop — сервис @MainActor.
    private func startProgressTimer(service: AudioPlayerService) {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: Self.progressUpdateInterval,
            repeats: true
        ) { [weak self, weak service] _ in
            guard let self, let service else { return }
            Task { @MainActor in
                if let track = service.currentTrack {
                    self.update(service: service, track: track)
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

/// no-op реализация для платформ без ActivityKit (macOS).
#else

@MainActor
final class AudioLiveActivityManager {
    static let shared = AudioLiveActivityManager()
    private init() {}

    var areActivitiesEnabled: Bool { false }

    func sync(with service: AudioPlayerService) {}
}

#endif
