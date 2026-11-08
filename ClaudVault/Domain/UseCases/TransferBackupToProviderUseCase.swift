import Foundation

/// Переносит все облачные версии резервной копии из одного
/// облака в другое (Google Drive ↔ Dropbox ↔ OneDrive).
///
/// Безопасная последовательность:
/// 1. Копирование каждой версии в целевое облако через
///    `TransferEngine` (чанки → resumable-сессия → верификация
///    размера и хешей). Исходные объекты не трогаем.
/// 2. Обновление `cloudObjectID` версий и `storageProvider`
///    записи — только после успешного копирования всех версий.
/// 3. При `move == true` исходные объекты удаляются из
///    исходного облака (best-effort: дубликат безопаснее,
///    чем потеря данных).
@MainActor
final class TransferBackupToProviderUseCase {

    private let backupRepository: BackupMetadataRepository
    private let cloudStorageRepository: CloudStorageRepository
    /// Репозитории всех облаков; `nil` — только Google Drive.
    private let repositories: [StorageProviderType: CloudStorageRepository]?
    /// nil — legacy-путь через временный файл.
    private let transferEngine: TransferEngine?

    init(
        backupRepository: BackupMetadataRepository,
        cloudStorageRepository: CloudStorageRepository,
        repositories: [StorageProviderType: CloudStorageRepository]? = nil,
        transferEngine: TransferEngine? = nil
    ) {
        self.backupRepository = backupRepository
        self.cloudStorageRepository = cloudStorageRepository
        self.repositories = repositories
        self.transferEngine = transferEngine
    }

    private func repository(
        for provider: StorageProviderType
    ) -> CloudStorageRepository {
        repositories?[provider]
            ?? repositories?[.googleDrive]
            ?? cloudStorageRepository
    }

    /// Копирует (`move == false`) или перемещает (`move == true`)
    /// все версии записи в облако `target`.
    /// `progressHandler` получает общий прогресс 0...1.
    func execute(
        record: BackupRecord,
        to target: StorageProviderType,
        move: Bool,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws {
        let sourceProvider = record.storageProvider
        guard sourceProvider != target else {
            throw CloudStorageError.operationFailed(
                "Файл уже находится в этом облаке."
            )
        }
        guard sourceProvider != .unknown, target != .unknown else {
            throw CloudStorageError.operationFailed(
                "Облако источника не определено."
            )
        }

        let sourceRepo = repository(for: sourceProvider)
        let targetRepo = repository(for: target)

        let versions = try backupRepository.fetchVersions(for: record.id)
        guard !versions.isEmpty else {
            throw CloudStorageError.operationFailed(
                "У резервной копии нет загруженных версий."
            )
        }

        // Подменяем onProgress движка на время переноса,
        // чтобы прогресс шёл в UI бэкапов; прежний обработчик
        // (из StoragesViewModel) восстанавливаем после.
        let previousProgressHandler = transferEngine?.onProgress
        defer { transferEngine?.onProgress = previousProgressHandler }

        var updatedVersions: [BackupVersion] = []
        var uploadedFiles: [(old: BackupVersion, new: CloudFile)] = []

        for (index, version) in versions.enumerated() {
            try Task.checkCancellation()

            let file = try await sourceRepo.fileMetadata(
                id: version.cloudObjectID
            )

            transferEngine?.onProgress = { fraction in
                let overall = (Double(index) + fraction)
                    / Double(versions.count)
                Task { @MainActor in
                    progressHandler(min(max(overall, 0), 1))
                }
            }

            let uploaded = try await copyVersion(
                file: file,
                sourceProvider: sourceProvider,
                sourceRepo: sourceRepo,
                targetProvider: target,
                targetRepo: targetRepo
            )

            uploadedFiles.append((version, uploaded))
            updatedVersions.append(
                BackupVersion(
                    id: version.id,
                    backupRecordID: version.backupRecordID,
                    fileSize: uploaded.sizeBytes ?? version.fileSize,
                    checksum: version.checksum,
                    cloudObjectID: uploaded.id,
                    uploadedAt: version.uploadedAt
                )
            )
        }

        // Все версии скопированы и проверены — обновляем метаданные.
        for updated in updatedVersions {
            try backupRepository.updateVersion(updated)
        }
        var updatedRecord = record
        updatedRecord.storageProvider = target
        updatedRecord.updatedAt = .now
        try backupRepository.saveRecord(updatedRecord)

        // Move: удаляем исходные объекты только после того,
        // как метаданные уже указывают на новые. Best-effort:
        // дубликат в исходном облаке безопаснее потери данных.
        if move {
            for pair in uploadedFiles {
                try? await sourceRepo.deleteFile(id: pair.old.cloudObjectID)
            }
        }
    }

    /// Копирует одну версию: основной путь — TransferEngine
    /// (чанки + верификация), fallback — временный файл.
    private func copyVersion(
        file: CloudFile,
        sourceProvider: StorageProviderType,
        sourceRepo: CloudStorageRepository,
        targetProvider: StorageProviderType,
        targetRepo: CloudStorageRepository
    ) async throws -> CloudFile {
        if let engine = transferEngine {
            do {
                return try await engine.transferFile(
                    file,
                    from: sourceProvider.rawValue,
                    source: sourceRepo,
                    to: targetProvider.rawValue,
                    target: targetRepo,
                    targetParentID: nil,
                    move: false
                )
            } catch CloudStorageError.notImplemented {
                // Нет chunked-поддержки — legacy-путь ниже.
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "backup-transfer-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let safeName = SafeFileName.sanitized(
            file.name,
            fallback: "download-\(UUID().uuidString)"
        )
        let localURL = tempDir.appendingPathComponent(safeName)
        try await sourceRepo.downloadFile(
            id: file.id,
            to: localURL,
            progressHandler: nil
        )
        let uploaded = try await targetRepo.uploadFile(
            at: localURL,
            parentFolderID: nil
        ) { _ in }

        // Проверка размера до возврата — источник пока жив,
        // но метаданные не тронуты, так что ошибка безопасна.
        let meta = try await targetRepo.fileMetadata(id: uploaded.id)
        if let expected = file.sizeBytes, let actual = meta.sizeBytes,
           expected != actual {
            throw CloudStorageError.operationFailed(
                "Размер загруженного файла не совпадает с источником."
            )
        }
        return uploaded
    }
}
