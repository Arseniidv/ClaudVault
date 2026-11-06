import Foundation

@MainActor
final class CreateBackupWithUploadUseCase {
    private let backupRepository: BackupMetadataRepository
    private let cloudStorageRepository: CloudStorageRepository
    private let fileHasher: FileHashing
    private let fileAccessRepository: FileAccessRepository
    private let uploadSessionRepository: UploadSessionRepository
    private let saveUploadSessionUseCase: SaveUploadSessionUseCase
    private let updateUploadProgressUseCase: UpdateUploadProgressUseCase
    var errorMessage:String? = nil

    init(
        backupRepository: BackupMetadataRepository,
        cloudStorageRepository: CloudStorageRepository,
        fileHasher: FileHashing,
        fileAccessRepository: FileAccessRepository,
        uploadSessionRepository: UploadSessionRepository,
        saveUploadSessionUseCase: SaveUploadSessionUseCase,
        updateUploadProgressUseCase: UpdateUploadProgressUseCase
    ) {
        self.backupRepository = backupRepository
        self.cloudStorageRepository = cloudStorageRepository
        self.fileHasher = fileHasher
        self.fileAccessRepository = fileAccessRepository
        self.uploadSessionRepository = uploadSessionRepository
        self.saveUploadSessionUseCase = saveUploadSessionUseCase
        self.updateUploadProgressUseCase = updateUploadProgressUseCase
    }

    /// Создаёт резервную копию с загрузкой в облако.
    ///
    /// - Если для `sourceIdentifier` уже есть запись и последняя версия
    ///   имеет тот же SHA-256 — новая копия не создаётся.
    /// - Прогресс передачи отражается в `UploadSession` (Active Transfers).
    func execute(
        fileName: String,
        sourceIdentifier: String,
        fileURL: URL,
        parentFolderID: String?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> BackupRecord {

        // Удерживаем security-scoped доступ на всё время операции.
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let checksum = try fileHasher.hashFile(at: fileURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
            throw BackupError.fileSizeUnavailable
        }

        let record: BackupRecord
        if let existing = try? backupRepository.fetchRecord(bySource: sourceIdentifier) {
            record = existing
        } else {
            record = BackupRecord(
                id: UUID(),
                fileName: fileName,
                sourceIdentifier: sourceIdentifier
            )
            try backupRepository.saveRecord(record)
        }

        // Дедупликация: файл не изменился с последней версии — копия не нужна.
        let existingVersions = (try? backupRepository.fetchVersions(for: record.id)) ?? []
        if existingVersions.first?.checksum == checksum {
            progressHandler(1.0)
            return record
        }

        // Сохраняем security-scoped bookmark исходного файла для повторного анализа.
        let bookmarkBase64 = try? fileAccessRepository
            .makeSecurityScopedBookmark(for: fileURL)
            .base64EncodedString()

        // Обновляем реквизиты записи (провайдер, локальный файл).
        var updatedRecord = record
        updatedRecord.storageProvider = .googleDrive
        updatedRecord.localFilePath = fileURL.path
        updatedRecord.localFileBookmark = bookmarkBase64
        updatedRecord.updatedAt = Date()
        try backupRepository.saveRecord(updatedRecord)

        // Сессия загрузки для Active Transfers.
        let uploadSession = UploadSession(
            id: UUID(),
            fileName: fileName,
            fileURL: fileURL,
            sessionURL: nil,
            totalBytes: fileSize,
            uploadedBytes: 0,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date(),
            backupRecordID: record.id
        )
        try await saveUploadSessionUseCase.execute(uploadSession)
        try await updateUploadProgressUseCase.execute(id: uploadSession.id, status: .uploading)

        // Реальный прогресс по чанкам -> UploadSession.uploadedBytes.
        let sessionID = uploadSession.id
        let updateProgress = updateUploadProgressUseCase
        let reporter = UploadProgressReporter { bytes in
            Task { @MainActor in
                try? await updateProgress.execute(
                    id: sessionID,
                    uploadedBytes: bytes
                )
                progressHandler(min(max(Double(bytes) / Double(fileSize), 0), 1))
            }
        }

        let cloudFile: CloudFile
        do {
            cloudFile = try await cloudStorageRepository.uploadFile(
                at: fileURL,
                parentFolderID: parentFolderID,
                progressHandler: { fraction in
                    reporter.report(fraction: fraction, totalBytes: fileSize)
                }
            )
        } catch {
            try? await updateUploadProgressUseCase.execute(id: sessionID, status: .failed)
            try? await updateUploadProgressUseCase.execute(
                id: sessionID,
                errorMessage: error.localizedDescription
            )
            throw error
        }

        let version = BackupVersion(
            id: UUID(),
            backupRecordID: record.id,
            fileSize: fileSize,
            checksum: checksum,
            cloudObjectID: cloudFile.id
        )
        try backupRepository.saveVersion(version, for: record.id)

        try await updateUploadProgressUseCase.execute(id: sessionID, uploadedBytes: fileSize)
        try await updateUploadProgressUseCase.execute(id: sessionID, status: .completed)
        try await updateUploadProgressUseCase.execute(id: sessionID, errorMessage: nil)

        updatedRecord.updatedAt = Date()
        try backupRepository.saveRecord(updatedRecord)

        progressHandler(1.0)
        return updatedRecord
    }

    enum BackupError: LocalizedError {
        case fileSizeUnavailable
        case hashCalculationFailed
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileSizeUnavailable:
                return "Не удалось получить размер файла."
            case .hashCalculationFailed:
                return "Не удалось вычислить хеш файла."
            case .uploadFailed(let message):
                return "Ошибка загрузки: \(message)"
            }
        }
    }
}
