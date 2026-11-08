import Foundation

@MainActor
final class DeleteBackupUseCase {
    private let backupRepository: BackupMetadataRepository
    private let cloudStorageRepository: CloudStorageRepository
    /// Репозитории всех облаков — удаление идёт из облака,
    /// указанного в `record.storageProvider`.
    private let repositories: [StorageProviderType: CloudStorageRepository]?

    init(
        backupRepository: BackupMetadataRepository,
        cloudStorageRepository: CloudStorageRepository,
        repositories: [StorageProviderType: CloudStorageRepository]? = nil
    ) {
        self.backupRepository = backupRepository
        self.cloudStorageRepository = cloudStorageRepository
        self.repositories = repositories
    }

    /// Репозиторий облака записи: `record.storageProvider`,
    /// при отсутствии — Google Drive (совместимость со старыми записями).
    private func repository(
        for record: BackupRecord
    ) -> CloudStorageRepository {
        repositories?[record.storageProvider]
            ?? repositories?[.googleDrive]
            ?? cloudStorageRepository
    }

    /// Репозиторий облака версии — через её запись.
    private func repository(
        for version: BackupVersion
    ) throws -> CloudStorageRepository {
        guard let record = backupRepository.fetchRecords(
            id: version.backupRecordID
        ) else {
            return cloudStorageRepository
        }
        return repository(for: record)
    }

    /// Удаляет отдельную версию резервной копии.
    /// Сначала удаляет облачный объект, затем метаданные.
    /// Если облачного объекта уже нет (404) — метаданные тоже удаляются.
    func execute(version: BackupVersion) async throws {
        do {
            try await repository(for: version).deleteFile(id: version.cloudObjectID)
        } catch CloudStorageError.notFound {
            // Объект уже удалён из облака — продолжаем с метаданными.
        } catch {
            throw DeleteError.cloudDeletionFailed(error.localizedDescription)
        }

        // Метаданные удаляются только после подтверждения удаления из облака.
        try backupRepository.deleteVersion(id: version.id)
    }

    /// Удаляет всю запись резервной копии со всеми версиями.
    /// Пытается удалить все облачные объекты; запись и метаданные
    /// удаляются только если все облачные удаления подтверждены.
    func execute(record: BackupRecord) async throws {
        let versions = try backupRepository.fetchVersions(for: record.id)
        let targetRepository = repository(for: record)

        var firstFailure: Error?
        for version in versions {
            do {
                try await targetRepository.deleteFile(id: version.cloudObjectID)
            } catch CloudStorageError.notFound {
                // Уже удалён — считаем успешным.
            } catch {
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }

        if let firstFailure {
            throw DeleteError.cloudDeletionFailed(
                "Не все файлы удалены из облака: \(firstFailure.localizedDescription)"
            )
        }

        // Запись (и каскадно все версии) удаляется только после
        // успешного удаления всех облачных объектов.
        try backupRepository.deleteRecord(id: record.id)
    }

    enum DeleteError: LocalizedError {
        case cloudDeletionFailed(String)
        case metadataDeletionFailed(String)

        var errorDescription: String? {
            switch self {
            case .cloudDeletionFailed(let message):
                return "Ошибка удаления из облака: \(message)"
            case .metadataDeletionFailed(let message):
                return "Ошибка удаления метаданных: \(message)"
            }
        }
    }
}
