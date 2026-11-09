import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import ClaudVaultDomain

/// Управляет Live Activities «синхронизация резервной копии»:
/// одна `Activity<CloudSyncAttributes>` на каждую активную
/// `UploadSession` (pending / uploading / paused).
///
/// Менеджер не вызывается из UI напрямую — он периодически
/// опрашивает `FetchUploadSessionsUseCase` и приводит набор
/// активностей в соответствие с реальными сессиями загрузки.
/// Поэтому Live Activity отражает все фоновые передачи:
/// создание копии, повторный анализ, retry — независимо от того,
/// открыт ли экран «Синхронизация».
///
/// Класс изолирован за `#if os(iOS)` — на macOS приложение
/// собирается без ActivityKit.
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

    private init() {}

    /// `false`, если пользователь запретил Live Activities в настройках
    /// (Настройки → ClaudVault → Live Activities) или на unsupported устройстве.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Monitoring

    /// Запускает фоновый мониторинг сессий загрузки: каждые ~1 c
    /// выгружает `UploadSession` и синхронизирует Live Activities.
    /// Вызывать один раз при старте приложения.
    func startMonitoring(fetchSessions: FetchUploadSessionsUseCase) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncOnce(fetchSessions: fetchSessions)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Останавливает мониторинг (например, при завершении приложения).
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
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

        // Завершённые и ошибочные — показываем финальное состояние один раз.
        for session in sessions where !Self.isActive(session.status) {
            guard !finalizedSessionIDs.contains(session.id) else { continue }
            finalizedSessionIDs.insert(session.id)

            let statusMessage = session.status == .completed
                ? "Завершено"
                : "Ошибка"
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

            await updateActivity(for: session)
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

    private static func statusMessage(for status: SessionStatus) -> String {
        switch status {
        case .pending: return "Подготовка к загрузке..."
        case .paused: return "Пауза"
        case .uploading: return "Загрузка..."
        case .completed: return "Завершено"
        case .failed: return "Ошибка"
        }
    }

    // MARK: - Activity lifecycle

    /// Запускает Live Activity для сессии загрузки.
    private func startActivity(
        id: UUID,
        fileName: String,
        providerName: String
    ) {
        let attributes = CloudSyncAttributes(
            fileName: fileName,
            providerName: providerName
        )
        let state = CloudSyncAttributes.ContentState(
            progress: 0,
            currentSpeed: "0 MB/s",
            statusMessage: "Подготовка к загрузке..."
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

    /// Обновляет прогресс активности по текущему состоянию сессии.
    private func updateActivity(for session: UploadSession) async {
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
            statusMessage: Self.statusMessage(for: session.status)
        )

        await activity.update(.init(state: state, staleDate: nil))
    }

    /// Завершает активность сессии и убирает её из реестра.
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
            statusMessage: statusMessage
        )

        await activity.end(
            .init(state: state, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(dismissAfter))
        )
    }

    // MARK: - Speed calculation

    /// Скорость по дельте между опросами; при слишком частых
    /// вызовах (<0.2 c) сохраняем прошлое значение, чтобы не мигало.
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

/// no-op реализация для платформ без ActivityKit (macOS).
#else

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    var areActivitiesEnabled: Bool { false }

    func startMonitoring(fetchSessions: FetchUploadSessionsUseCase) {}
    func stopMonitoring() {}
    func sync(with sessions: [UploadSession]) async {}
}

#endif
