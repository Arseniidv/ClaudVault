import Foundation

@MainActor
final class ReparseAndBackupUseCase {
    private let backupRepository: BackupMetadataRepository
    private let cloudStorageRepository: CloudStorageRepository
    private let fileHasher: FileHashing
    private let fileAccessRepository: FileAccessRepository
    private let uploadSessionRepository: UploadSessionRepository
    private let saveUploadSessionUseCase: SaveUploadSessionUseCase
    private let updateUploadProgressUseCase: UpdateUploadProgressUseCase

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

    /// Повторный анализ записи резервной копии.
    /// Восстанавливает доступ к исходному файлу через сохранённый
    /// security-scoped bookmark, пересчитывает SHA-256 и создаёт
    /// новую версию только если файл изменился.
    ///
    /// - Returns: новая `BackupVersion`, либо `nil` если файл не изменился.
    func execute(
        record: BackupRecord,
        parentFolderID: String?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> BackupVersion? {
        guard let bookmarkBase64 = record.localFileBookmark else {
            throw ReparseError.fileAccessLost
        }

        let fileURL = try fileAccessRepository.urlForBookmark(base64: bookmarkBase64)

        // Удерживаем security-scoped доступ на время хеширования и загрузки.
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try await performReparse(
            record: record,
            fileURL: fileURL,
            parentFolderID: parentFolderID,
            progressHandler: progressHandler
        )
    }

    /// Вариант по идентификатору записи и прямому URL файла.
    func execute(
        sourceIdentifier: String,
        fileURL: URL,
        parentFolderID: String?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> BackupVersion? {
        guard let record = try backupRepository.fetchRecord(bySource: sourceIdentifier) else {
            throw ReparseError.recordNotFound
        }
        return try await performReparse(
            record: record,
            fileURL: fileURL,
            parentFolderID: parentFolderID,
            progressHandler: progressHandler
        )
    }

    // MARK: - Core

    private func performReparse(
        record: BackupRecord,
        fileURL: URL,
        parentFolderID: String?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> BackupVersion? {
        // 1. Текущий SHA-256 файла.
        let currentChecksum = try fileHasher.hashFile(at: fileURL)

        // 2. Последняя сохранённая версия.
        let versions = try backupRepository.fetchVersions(for: record.id)
        guard let lastVersion = versions.first else {
            return try await createNewVersion(
                record: record,
                fileURL: fileURL,
                checksum: currentChecksum,
                parentFolderID: parentFolderID,
                progressHandler: progressHandler
            )
        }

        // 3. Файл не изменился — новую копию не создаём.
        if lastVersion.checksum == currentChecksum {
            progressHandler(1.0)
            return nil
        }

        return try await createNewVersion(
            record: record,
            fileURL: fileURL,
            checksum: currentChecksum,
            parentFolderID: parentFolderID,
            progressHandler: progressHandler
        )
    }

    private func createNewVersion(
        record: BackupRecord,
        fileURL: URL,
        checksum: String,
        parentFolderID: String?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> BackupVersion {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
            throw ReparseError.fileSizeUnavailable
        }

        let uploadSession = UploadSession(
            id: UUID(),
            fileName: record.fileName,
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

        var updatedRecord = record
        updatedRecord.updatedAt = Date()
        try backupRepository.saveRecord(updatedRecord)

        progressHandler(1.0)
        return version
    }

    enum ReparseError: LocalizedError {
        case recordNotFound
        case fileSizeUnavailable
        case hashCalculationFailed
        case uploadFailed(String)
        case fileAccessLost

        var errorDescription: String? {
            switch self {
            case .recordNotFound:
                return "Запись резервной копии не найдена."
            case .fileSizeUnavailable:
                return "Не удалось получить размер файла."
            case .hashCalculationFailed:
                return "Не удалось вычислить хеш файла."
            case .uploadFailed(let message):
                return "Ошибка загрузки: \(message)"
            case .fileAccessLost:
                return "Нет доступа к исходному файлу. Выберите файл заново."
            }
        }
    }
}
