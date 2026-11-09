import Foundation
import ClaudVaultDomain

#if os(iOS) && canImport(ActivityKit)
import ActivityKit


@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    /// Активные Live Activities, ключ — id `UploadSession`.
    private var activities: [UUID: Activity<CloudSyncAttributes>] = [:]

    /// Сессии, для которых финальное состояние уже показано —
    /// чтобы не завершать активность повторно на каждом опросе.
    private var finalizedSessionIDs: Set<UUID> = []

    /// Последние замеры прогресса для расчёта скорости — по session id.
    private var lastUploadedBytes: [UUID: Int64] = [:]
    private var lastUpdateDate: [UUID: Date] = [:]
    private var speedTexts: [UUID: String] = [:]

    private var monitoringTask: Task<Void, Never>?

    /// UseCase выборки сессий — нужен для внеплановых сверок
    /// по сигналу `sessionDidChange`.
    private var fetchSessions: FetchUploadSessionsUseCase?

    /// Запрос на немедленную сверку (новая сессия в репозитории).
    private var wakeRequested = false

    /// Быстрый режим нужен, пока есть активные сессии или
    /// завершённые, ещё не показанные финальным состоянием.
    private var hasPendingWork = false
    private init() {}
    /// `false`, если пользователь запретил Live Activities в настройках
    /// (Настройки → ClaudVault → Live Activities) или на unsupported устройстве.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Monitoring

    /// Запускает фоновый мониторинг сессий загрузки.
    /// Пока есть активные передачи — опрос каждую ~1 c; в простое
    /// интервал растягивается до 15 c, а новая сессия будит
    /// мониторинг через `sessionDidChange` без ожидания тика.
    /// Вызывать один раз при старте приложения.
    func startMonitoring(fetchSessions: FetchUploadSessionsUseCase) {
        self.fetchSessions = fetchSessions
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncOnce(fetchSessions: fetchSessions)
                await self?.sleepUntilNextPoll()
            }
        }
    }

    /// Останавливает мониторинг (например, при завершении приложения).
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Сигнал от `UploadSessionRepository` о сохранении сессии:
    /// будит мониторинг, чтобы Live Activity появилась сразу,
    /// а не на следующем медленном тике.
    nonisolated func sessionDidChange() {
        Task { @MainActor [weak self] in
            self?.wakeRequested = true
        }
    }

    private func sleepUntilNextPoll() async {
        let interval: TimeInterval =
            (hasPendingWork || !activities.isEmpty) ? 1 : 15
        let deadline = Date().addingTimeInterval(interval)
        while !Task.isCancelled {
            if wakeRequested {
                wakeRequested = false
                return
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(min(remaining, 0.5) * 1_000_000_000)
            )
        }
    }

    private func syncOnce(fetchSessions: FetchUploadSessionsUseCase) async {
        guard areActivitiesEnabled else { return }
        let sessions = (try? await fetchSessions.execute()) ?? []
        await sync(with: sessions)
    }

    /// Сверяет список сессий с активностями:
    /// активные → создать/обновить, завершённые → финализировать,
    /// удалённые → прервать.
    func sync(with sessions: [UploadSession]) async {
        guard areActivitiesEnabled else { return }

        let sessionIDs = Set(sessions.map(\.id))

        // Быстрый опрос нужен, пока есть активные сессии или
        // завершённые, которые ещё не показали финальное состояние.
        hasPendingWork = sessions.contains { session in
            Self.isActive(session.status)
                || !finalizedSessionIDs.contains(session.id)
        }
        finalizedSessionIDs = finalizedSessionIDs.filter {
            sessionIDs.contains($0)
        }

        // Завершённые и ошибочные — показываем финальное состояние один раз.
        for session in sessions where !Self.isActive(session.status) {
            // Флаг отмены больше не нужен: загрузка уже завершилась.
            UploadCancellation.clear(session.id)

            guard !finalizedSessionIDs.contains(session.id) else { continue }
            finalizedSessionIDs.insert(session.id)

            let statusMessage: String
            switch session.status {
            case .completed:
                statusMessage = "Завершено"
            case .failed:
                statusMessage = Self.isCancellationMessage(session.errorMessage)
                    ? "Отменено"
                    : "Ошибка"
            default:
                statusMessage = "Прервано"
            }
            let finalProgress = session.status == .completed
                ? 1.0
                : session.progress
            await endActivity(
                id: session.id,
                statusMessage: statusMessage,
                progress: finalProgress,
                dismissAfter: 5
            )
        }

        // Активные — создаём активность при первом появлении
        // и обновляем состояние.
        for session in sessions where Self.isActive(session.status) {
            finalizedSessionIDs.remove(session.id)

            if activities[session.id] == nil {
                startActivity(
                    id: session.id,
                    fileName: session.fileName,
                    providerName: "Google Drive"
                )
            }

            // Сессия активна — кнопка «Отменить» доступна.
            await updateActivity(for: session, canCancel: true)
        }

        // Сессии, которых больше нет в хранилище (удалены
        // пользователем из «Синхронизации»), — прерываем.
        let staleIDs = activities.keys.filter { !sessionIDs.contains($0) }
        for id in staleIDs {
            await endActivity(
                id: id,
                statusMessage: "Прервано",
                progress: 0,
                dismissAfter: 1
            )
        }

        // Подчистка bookkeeping по удалённым сессиям.
        speedTexts = speedTexts.filter { sessionIDs.contains($0.key) }
        lastUploadedBytes = lastUploadedBytes.filter { sessionIDs.contains($0.key) }
        lastUpdateDate = lastUpdateDate.filter { sessionIDs.contains($0.key) }
    }

    private static func isActive(_ status: SessionStatus) -> Bool {
        status == .pending || status == .uploading || status == .paused
    }

    /// `errorMessage` сессии означает отмену пользователем —
    /// Live Activity показывает «Отменено» вместо «Ошибка».
    private static func isCancellationMessage(_ message: String?) -> Bool {
        message?.localizedCaseInsensitiveContains("отмен") == true
    }

    private static func statusMessage(for status: SessionStatus) -> String {
        switch status {
        case .pending: return "Подготовка к загрузке..."
        case .paused: return "Пауза"
        case .uploading: return "Загрузка..."
        case .completed: return "Завершено"
        case .failed: return "Ошибка"
        }
    }


    /// Запускает Live Activity для сессии загрузки.
    private func startActivity(
        id: UUID,
        fileName: String,
        providerName: String
    ) {
        let attributes = CloudSyncAttributes(
            fileName: fileName,
            providerName: providerName,
            sessionID: id.uuidString
        )
        let state = CloudSyncAttributes.ContentState(
            progress: 0,
            currentSpeed: "0 MB/s",
            statusMessage: "Подготовка к загрузке...",
            canCancel: true
        )

        if let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        ) {
            activities[id] = activity
        }

        lastUploadedBytes[id] = 0
        lastUpdateDate[id] = Date()
        speedTexts[id] = "0 MB/s"
    }
    

    private func updateActivity(for session: UploadSession, canCancel: Bool) async {
        guard let activity = activities[session.id] else { return }

        let progress = min(max(session.progress, 0), 1)
        let speedText = Self.speedText(
            for: session.id,
            uploadedBytes: session.uploadedBytes,
            totalBytes: session.totalBytes,
            speedTexts: &speedTexts,
            lastUploadedBytes: &lastUploadedBytes,
            lastUpdateDate: &lastUpdateDate
        )

        let state = CloudSyncAttributes.ContentState(
            progress: progress,
            currentSpeed: speedText,
            statusMessage: Self.statusMessage(for: session.status),
            canCancel: canCancel
        )

        await activity.update(.init(state: state, staleDate: nil))
    }

    @MainActor
    private func endActivity(
        id: UUID,
        statusMessage: String,
        progress: Double = 1,
        dismissAfter: TimeInterval = 5
    ) async {
        guard let activity = activities.removeValue(forKey: id) else { return }

        let lastSpeed = speedTexts[id] ?? "0 MB/s"
        lastUploadedBytes[id] = nil
        lastUpdateDate[id] = nil
        speedTexts[id] = nil

        let state = CloudSyncAttributes.ContentState(
            progress: min(max(progress, 0), 1),
            currentSpeed: lastSpeed,
            statusMessage: statusMessage,
            canCancel: false
        )

        await activity.end(
            .init(state: state, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(dismissAfter))
        )
    }

    // MARK: - Speed calculation

    private static func speedText(
        for sessionID: UUID,
        uploadedBytes: Int64,
        totalBytes: Int64,
        speedTexts: inout [UUID: String],
        lastUploadedBytes: inout [UUID: Int64],
        lastUpdateDate: inout [UUID: Date]
    ) -> String {
        let now = Date()
        var text = speedTexts[sessionID] ?? "0 MB/s"

        if let lastDate = lastUpdateDate[sessionID] {
            let elapsed = now.timeIntervalSince(lastDate)
            if elapsed > 0.2 {
                let delta = Double(uploadedBytes - (lastUploadedBytes[sessionID] ?? 0))
                if delta >= 0 {
                    text = formatSpeed(delta / elapsed)
                }
            }
        }

        lastUploadedBytes[sessionID] = uploadedBytes
        lastUpdateDate[sessionID] = now
        speedTexts[sessionID] = text
        return text
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_000_000
        if mb >= 1 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = bytesPerSecond / 1_000
        return String(format: "%.0f KB/s", kb)
    }
}
#else

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    var areActivitiesEnabled: Bool { false }

    func startMonitoring(fetchSessions: FetchUploadSessionsUseCase) {}
    func stopMonitoring() {}
    nonisolated func sessionDidChange() {}
    func sync(with sessions: [UploadSession]) async {}
}

#endif
