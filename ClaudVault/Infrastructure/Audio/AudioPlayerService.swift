import Foundation
import AVFoundation
import MediaPlayer
#if os(iOS)
import AVFAudio
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Единый аудиоплеер приложения: единственный `AVPlayer`
/// на процесс. Управляет очередью треков, системными командами
/// (MPRemoteCommandCenter), Now Playing info, фоновой аудиосессией
/// (iOS) и публикует безопасный снимок состояния в App Group
/// для виджета и Live Activity.
///
/// Виджет и Live Activity не имеют доступа к этому объекту —
/// они работают через `AudioCommandBus` (Darwin-уведомления)
/// и `AudioPlayerSnapshot` в `UserDefaults` App Group.
@MainActor
@Observable
final class AudioPlayerService {

    /// Общий экземпляр: плеер — синглтон на всё приложение,
    /// окна macOS и view'и используют один и тот же AVPlayer.
    static let shared = AudioPlayerService()

    /// Резолвер облачных источников. Устанавливается из
    /// `AppDependencies` после создания репозиториев.
    var resolver: AudioSourceResolver?

    // MARK: - Observable state

    private(set) var queue: [AudioTrack] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var isLoading = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var volume: Float = 1
    private(set) var repeatMode: AudioRepeatMode = .all
    private(set) var shuffleEnabled = false
    private(set) var errorMessage: String?

    var currentTrack: AudioTrack? {
        guard let currentIndex, queue.indices.contains(currentIndex) else {
            return nil
        }
        return queue[currentIndex]
    }

    var hasNextTrack: Bool {
        currentIndex != nil
    }

    var hasPreviousTrack: Bool {
        currentIndex != nil
    }

    // MARK: - Internals

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var commandObserver: AudioCommandBus.ObserverToken?
    private var resolveTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    /// Имя JPEG-файла обложки в App Group (для виджета/Live Activity).
    /// Читается `AudioLiveActivityManager` при обновлении активности.
    private(set) var artworkFileName: String?

    /// Троттлинг публикации снимка: позиция обновляется
    /// каждые 0.5 c, но в App Group пишем не чаще
    /// `publishInterval` — промежуточные тики отбрасываются.
    private var lastPublishAt = Date.distantPast

    private static let volumeDefaultsKey = "audioPlayerVolume"
    private static let publishInterval: TimeInterval = 2

    private init() {
        volume = Float(
            UserDefaults.standard.double(forKey: Self.volumeDefaultsKey)
        )
        // Дефолт 1.0: double(forKey:) несуществующего ключа = 0.
        if UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) == nil {
            volume = 1
        }
    }

    // MARK: - Activation

    /// Вызывается один раз при старте приложения: настраивает
    /// аудиосессию, системные команды и шину команд виджета.
    func activate() {
        #if os(iOS)
        configureAudioSession()
        #endif
        configureRemoteCommands()
        observeWidgetCommands()
    }

    // MARK: - Playback control

    /// Запускает воспроизведение очереди с указанного трека.
    func play(queue newQueue: [AudioTrack], startIndex: Int = 0) {
        guard !newQueue.isEmpty else { return }
        queue = newQueue
        currentIndex = min(max(startIndex, 0), newQueue.count - 1)
        errorMessage = nil
        isLoading = true
        position = 0
        duration = 0
        artworkFileName = nil
        publishSnapshot(force: true)
        loadCurrentTrack()
    }

    /// Удобный шорткат: очередь из одного трека.
    func play(track: AudioTrack) {
        play(queue: [track], startIndex: 0)
    }

    /// Добавляет треки в конец очереди (не прерывая воспроизведение).
    func enqueue(_ tracks: [AudioTrack]) {
        queue.append(contentsOf: tracks)
        publishSnapshot(force: true)
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            if player == nil || currentTrack == nil {
                if let index = currentIndex, queue.indices.contains(index) {
                    loadCurrentTrack()
                }
                return
            }
            player?.play()
        }
        // isPlaying обновится через KVO timeControlStatus.
    }

    func play() {
        togglePlayPause()
    }

    func pause() {
        if isPlaying { player?.pause() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        // Одиночный трек: «дальше» — это повтор или стоп
        // в зависимости от режима повтора.
        if queue.count == 1 {
            if repeatMode == .off {
                pause()
            } else {
                replayCurrent()
            }
            return
        }
        let target: Int
        if shuffleEnabled {
            var candidate = Int.random(in: 0..<queue.count)
            if candidate == currentIndex {
                candidate = (candidate + 1) % queue.count
            }
            target = candidate
        } else {
            let nextIndex = (currentIndex ?? -1) + 1
            if nextIndex < queue.count {
                target = nextIndex
            } else if repeatMode == .all {
                target = 0
            } else {
                // Конец очереди: останавливаемся.
                pause()
                return
            }
        }
        play(index: target)
    }

    func previous() {
        guard !queue.isEmpty, let index = currentIndex else { return }
        // Стандартное поведение: если прошло >3 c —
        // возвращаемся в начало трека, иначе предыдущий.
        if position > 3 {
            seek(to: 0)
            return
        }
        if index > 0 {
            play(index: index - 1)
        } else if repeatMode == .all && queue.count > 1 {
            play(index: queue.count - 1)
        } else {
            seek(to: 0)
        }
    }

    private func replayCurrent() {
        seek(to: 0)
        player?.play()
    }

    private func play(index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        errorMessage = nil
        isLoading = true
        position = 0
        duration = 0
        artworkFileName = nil
        publishSnapshot(force: true)
        loadCurrentTrack()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        position = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateNowPlayingInfo()
            }
        }
        publishSnapshot()
    }

    func skip(by interval: TimeInterval) {
        seek(to: position + interval)
    }

    func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(newVolume, 1))
        volume = clamped
        player?.volume = clamped
        UserDefaults.standard.set(
            Double(clamped),
            forKey: Self.volumeDefaultsKey
        )
        publishSnapshot()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        publishSnapshot(force: true)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        publishSnapshot(force: true)
    }

    /// Полная остановка: пауза, очистка очереди, завершение
    /// Live Activity. Используется при выходе из аккаунта
    /// и по явной команде «остановить».
    func stopAndClear() {
        resolveTask?.cancel()
        metadataTask?.cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        queue = []
        currentIndex = nil
        position = 0
        duration = 0
        isPlaying = false
        isLoading = false
        isBuffering = false
        errorMessage = nil
        artworkFileName = nil
        publishSnapshot(force: true)
    }

    // MARK: - Track loading

    private func loadCurrentTrack() {
        guard let index = currentIndex,
              queue.indices.contains(index) else { return }
        let track = queue[index]
        guard let resolver else {
            errorMessage = "Плеер не инициализирован"
            isLoading = false
            publishSnapshot(force: true)
            return
        }

        resolveTask?.cancel()
        metadataTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await resolver.resolve(track)
                try Task.checkCancellation()
                self.applySource(source, trackIndex: index)
            } catch is CancellationError {
                // Переключение трека — нормальная гонка.
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.publishSnapshot(force: true)
            }
        }
        resolveTask = task
    }

    /// Создаёт/переназначает AVPlayerItem для текущего трека.
    private func applySource(
        _ source: ResolvedAudioSource,
        trackIndex: Int
    ) {
        guard currentIndex == trackIndex,
              queue.indices.contains(trackIndex) else { return }
        let trackID = queue[trackIndex].id

        var options: [String: Any] = [:]
        if !source.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = source.headers
        }
        let asset = AVURLAsset(url: source.url, options: options)
        let item = AVPlayerItem(asset: asset)

        ensurePlayer()
        player?.replaceCurrentItem(with: item)
        attachItemObservers(item: item, trackIndex: trackIndex)

        // Длительность — асинхронно, не блокируя UI.
        Task { [weak self] in
            guard let self else { return }
            if let cmDuration = try? await asset.load(.duration) {
                let seconds = cmDuration.seconds
                if seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
            }
            if self.duration == 0, let known = self.currentTrack?.knownDuration {
                self.duration = known
            }
            self.isLoading = false
            self.player?.play()
            self.publishSnapshot(force: true)
        }

        // Метаданные и обложка — после готовности item.
        metadataTask = Task { [weak self] in
            guard let self else { return }
            // Небольшая задержка не нужна: load(.commonMetadata)
            // читает только заголовки файла/потока.
            let metadata = await AudioMetadataExtractor.extract(
                from: asset
            )
            guard !Task.isCancelled,
                  self.currentIndex == trackIndex,
                  self.currentTrack?.id == trackID
            else { return }

            var updated = false
            if let index = self.currentIndex,
               self.queue.indices.contains(index) {
                if let title = metadata.title {
                    self.queue[index].title = title
                    updated = true
                }
                if let artist = metadata.artist {
                    self.queue[index].artist = artist
                    updated = true
                }
                if let album = metadata.album {
                    self.queue[index].album = album
                    updated = true
                }
                if let rawArtwork = metadata.artworkData,
                   let jpeg = AudioMetadataExtractor.jpegData(from: rawArtwork) {
                    self.queue[index].artworkJPEG = jpeg
                    self.artworkFileName = AudioArtworkStore.save(
                        jpeg,
                        for: self.queue[index].id
                    )
                    updated = true
                }
            }
            if updated {
                self.publishSnapshot(force: true)
            }
            self.updateNowPlayingInfo()
        }
    }

    private func ensurePlayer() {
        guard player == nil else {
            player?.volume = volume
            return
        }
        let player = AVPlayer()
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        self.player = player

        // Кнопки Now Playing отражают текущую очередь.
        updateNowPlayingInfo()

        // Позиция — каждые 0.5 c.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.position = time.seconds.isFinite ? time.seconds : 0
                self.publishSnapshot()
            }
        }

        // Статус воспроизведения (play/pause/buffering) —
        // через KVO: надёжнее ручных флагов при прерываниях.
        playerStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] player, _ in
            guard let self else { return }
            let status = player.timeControlStatus
            Task { @MainActor in
                self.isPlaying = status == .playing
                self.isBuffering =
                    status == .waitingToPlayAtSpecifiedRate
                self.publishSnapshot()
            }
        }
    }

    private func attachItemObservers(
        item: AVPlayerItem,
        trackIndex: Int
    ) {
        if let old = endObserver {
            NotificationCenter.default.removeObserver(old)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleTrackEnded()
            }
        }

        itemStatusObservation = item.observe(
            \.status,
            options: [.new]
        ) { [weak self] item, _ in
            guard let self else { return }
            let status = item.status
            let error = item.error
            Task { @MainActor in
                guard self.currentIndex == trackIndex
                else { return }
                switch status {
                case .failed:
                    self.isLoading = false
                    self.errorMessage = error?
                        .localizedDescription
                        ?? "Не удалось воспроизвести файл"
                    self.publishSnapshot(force: true)
                case .readyToPlay:
                    self.isLoading = false
                    self.updateNowPlayingInfo()
                default:
                    break
                }
            }
        }
    }

    private func handleTrackEnded() {
        guard currentIndex != nil else { return }
        if repeatMode == .one {
            replayCurrent()
            return
        }
        // Переход к следующему; если очередь кончилась и repeat
        // выключен — next() сам сделает pause.
        next()
    }

    // MARK: - Widget command channel

    /// Читает команду из App Group и исполняет.
    /// Вызывается по Darwin-уведомлению из расширения.
    private func observeWidgetCommands() {
        commandObserver = AudioCommandBus.observe { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleWidgetCommand()
            }
        }
    }

    private func handleWidgetCommand() {
        guard let command = AudioCommandBus.consumeLatest() else { return }
        switch command {
        case .togglePlayPause: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .toggleShuffle: toggleShuffle()
        case .cycleRepeat: cycleRepeatMode()
        }
    }

    // MARK: - Snapshot publishing

    /// Публикует безопасный снимок в App Group:
    /// виджет и Live Activity читают его из `UserDefaults`.
    /// Токены и URL сюда не попадают.
    private func publishSnapshot(force: Bool = false) {
        let now = Date()
        // Позиция меняется каждые 0.5 c — пишем не чаще
        // publishInterval, кроме принудительных обновлений
        // (смена трека, play/pause, shuffle/repeat).
        if !force,
           now.timeIntervalSince(lastPublishAt) < Self.publishInterval {
            return
        }
        lastPublishAt = now

        let snapshot = AudioPlayerSnapshot(
            track: widgetTrack(),
            volume: Double(volume),
            errorMessage: errorMessage,
            updatedAt: now
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(
                  suiteName: WidgetStorage.appGroupID
              )
        else { return }
        defaults.set(data, forKey: AudioWidgetConfig.snapshotKey)

        // Перезагрузка таймлайна нужна только при смене
        // отображаемого состояния — позиция обновляется
        // внутри виджета через `Text(timerInterval:)`.
        if force {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(
                ofKind: AudioWidgetConfig.widgetKind
            )
            #endif
        }

        AudioLiveActivityManager.shared.sync(with: self)
    }

    private func widgetTrack() -> WidgetAudioTrack? {
        guard let index = currentIndex,
              queue.indices.contains(index) else { return nil }
        let track = queue[index]
        let effectiveDuration = duration > 0 ? duration : track.duration
        return WidgetAudioTrack(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            providerName: track.provider.rawValue,
            fileName: track.fileName,
            duration: effectiveDuration,
            position: min(position, effectiveDuration > 0 ? effectiveDuration : position),
            isPlaying: isPlaying,
            isLoading: isLoading || isBuffering,
            repeatMode: repeatMode.rawValue,
            shuffleEnabled: shuffleEnabled,
            artworkFileName: artworkFileName,
            queueIndex: index + 1,
            queueCount: queue.count,
            hasNext: hasNextTrack,
            hasPrevious: hasPreviousTrack,
            updatedAt: Date()
        )
    }

    // MARK: - Audio session (iOS)

    #if os(iOS)
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try session.setActive(true)
        } catch {
            // Категория могла быть настроена ранее — не критично.
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // queue: .main — уже главный поток, hops через Task
            // не нужен; assumeIsolated даёт actor-контекст без
            // захвата non-Sendable Notification в @Sendable-код.
            MainActor.assumeIsolated {
                self?.handleInterruption(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? UInt,
            let type = AVAudioSession.InterruptionType(
                rawValue: typeValue
            )
        else { return }

        switch type {
        case .began:
            // Звонок/Siri — приостанавливаем.
            player?.pause()
        case .ended:
            guard let optionsValue = notification.userInfo?[
                AVAudioSessionInterruptionOptionKey
            ] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(
                rawValue: optionsValue
            )
            if options.contains(.shouldResume) {
                player?.play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[
            AVAudioSessionRouteChangeReasonKey
        ] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(
                rawValue: reasonValue
            )
        else { return }
        // Отключили наушники — ставим на паузу,
        // чтобы звук не пошёл из динамика.
        if reason == .oldDeviceUnavailable {
            player?.pause()
        }
    }
    #endif

    // MARK: - Remote commands & Now Playing

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            Task { @MainActor in
                self?.seek(to: event.positionTime)
            }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 10) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -10) }
            return .success
        }
    }

    private func remotePlay() {
        if player == nil {
            togglePlayPause()
        } else {
            player?.play()
        }
    }

    private func remotePause() {
        player?.pause()
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? track.fileName,
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork = currentArtworkImage() {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Enabled-состояние кнопок отражает очередь.
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNextTrack
        center.previousTrackCommand.isEnabled = hasPreviousTrack
    }

    /// Обложка для Now Playing: JPEG из метаданных трека.
    private func currentArtworkImage() -> MPMediaItemArtwork? {
        guard let index = currentIndex,
              queue.indices.contains(index),
              let data = queue[index].artworkJPEG
        else { return nil }

        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        #else
        guard let image = NSImage(data: data) else { return nil }
        #endif

        let artwork = MPMediaItemArtwork(
            boundsSize: image.size
        ) { _ in image }
        return artwork
    }
}
