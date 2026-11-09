import Foundation
import Observation
import ClaudVaultDomain

/// Преобразует `UploadSession` (SwiftData) в задачи для экрана
/// «Синхронизация» и периодически обновляет их.
@MainActor
@Observable
final class SynchronizationViewModel {

    private let fetchUploadSessions: FetchUploadSessionsUseCase
    private let updateUploadProgress: UpdateUploadProgressUseCase
    private let backupMetadataRepository: BackupMetadataRepository
    private let reparseAndBackup: ReparseAndBackupUseCase

    private(set) var sessions: [UploadSession] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// Текущая скорость передачи, МБ/с (по последним двум замерам).
    private(set) var currentSpeedMBps: Double = 0

    private var pollingTask: Task<Void, Never>?
    private var lastActiveBytes: Int64 = 0
    private var lastSampleDate: Date?

    init(
        fetchUploadSessions: FetchUploadSessionsUseCase,
        updateUploadProgress: UpdateUploadProgressUseCase,
        backupMetadataRepository: BackupMetadataRepository,
        reparseAndBackup: ReparseAndBackupUseCase
    ) {
        self.fetchUploadSessions = fetchUploadSessions
        self.updateUploadProgress = updateUploadProgress
        self.backupMetadataRepository = backupMetadataRepository
        self.reparseAndBackup = reparseAndBackup
    }

    // MARK: - Derived state

    var activeTasks: [SyncTask] {
        sessions
            .filter { $0.status == .pending || $0.status == .uploading || $0.status == .paused }
            .map { toTask($0) }
    }

    var completedTasks: [SyncTask] {
        sessions
            .filter { $0.status == .completed }
            .map { toTask($0) }
    }

    var failedSessions: [UploadSession] {
        sessions.filter { $0.status == .failed }
    }

    var hasActiveTransfers: Bool {
        !activeTasks.isEmpty
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await fetchUploadSessions.execute()
            sessions = fetched.sorted(by: { $0.updatedAt > $1.updatedAt })
            updateSpeedEstimate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Запускает периодическое обновление (1 раз в секунду).
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Delete

    /// Удаляет сессию передачи из истории — любого статуса
    /// (активная, failed, completed).
    func deleteSession(id: UUID) {
        Task {
            do {
                try await updateUploadProgress.executeDelete(id: id)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Retry

    /// Повторяет неудавшуюся передачу: повторный анализ записи
    /// (новая версия создаётся только при изменении файла).
    func retry(_ session: UploadSession) {
        guard let recordID = session.backupRecordID,
              let record = backupMetadataRepository.fetchRecords(id: recordID) else {
            errorMessage = "Не удалось найти резервную копию для повторной передачи."
            return
        }

        Task {
            do {
                _ = try await reparseAndBackup.execute(
                    record: record,
                    parentFolderID: nil
                ) { _ in }

                // Повторная попытка обработана — убираем failed-сессию.
                try? await updateUploadProgress.executeDelete(id: session.id)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
                await refresh()
            }
        }
    }

    // MARK: - Mapping

    private func toTask(_ session: UploadSession) -> SyncTask {
        let totalMB = Double(session.totalBytes) / 1_048_576
        let transferredMB = Double(session.uploadedBytes) / 1_048_576

        let status: SyncTaskStatus
        switch session.status {
        case .completed:
            status = .completed
        case .failed:
            status = .failed
        case .pending, .uploading, .paused:
            status = .transferring
        }

        return SyncTask(
            id: session.id,
            fileName: session.fileName,
            source: "Local",
            destination: "Google Drive",
            progress: session.progress,
            transferredSize: transferredMB,
            totalSize: totalMB,
            speed: currentSpeedMBps,
            remainingTime: remainingTimeText(for: session),
            status: status
        )
    }

    private func remainingTimeText(for session: UploadSession) -> String {
        guard session.status == .uploading || session.status == .pending,
              currentSpeedMBps > 0 else {
            return session.status == .completed ? "Готово" : "—"
        }

        let remainingBytes = Double(session.totalBytes - session.uploadedBytes)
        guard remainingBytes > 0 else { return "Завершается" }

        let remainingSeconds = remainingBytes / (currentSpeedMBps * 1_048_576)
        if remainingSeconds < 60 {
            return "≈ \(Int(remainingSeconds)) с"
        }
        return "≈ \(Int(remainingSeconds / 60)) мин"
    }

    /// Оценивает скорость по разнице суммарно переданных байт
    /// между соседними опросами.
    private func updateSpeedEstimate() {
        let now = Date()
        let activeBytes = sessions
            .filter { $0.status == .uploading || $0.status == .pending }
            .reduce(Int64(0)) { $0 + $1.uploadedBytes }

        if let lastDate = lastSampleDate {
            let elapsed = now.timeIntervalSince(lastDate)
            if elapsed > 0 {
                let deltaBytes = Double(activeBytes - lastActiveBytes)
                if deltaBytes >= 0 {
                    currentSpeedMBps = (deltaBytes / elapsed) / 1_048_576
                }
            }
        }

        lastActiveBytes = activeBytes
        lastSampleDate = now
    }
}
