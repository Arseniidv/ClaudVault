import Foundation

/// Переименование резервной копии: облачные объекты всех версий
/// переименовываются через API провайдера, затем обновляется
/// `record.fileName`. Новая версия/копия не создаётся.
@MainActor
public final class RenameBackupUseCase {
    private let backupRepository: BackupMetadataRepository
    private let cloudStorageRepository: CloudStorageRepository
    /// Репозитории всех облаков — переименование идёт в облако,
    /// указанное в `record.storageProvider`.
    private let repositories: [StorageProviderType: CloudStorageRepository]?

    public init(
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

    /// Переименовывает запись и облачные объекты всех её версий.
    ///
    /// Если облачное переименование не удалось, локальное имя
    /// не меняется — операцию можно повторить (rename идемпотентен).
    /// Объекты, которых уже нет в облаке (404) или провайдер
    /// не поддерживает rename, пропускаются.
    ///
    /// - Returns: обновлённая запись.
    @discardableResult
    public func execute(record: BackupRecord, newName: String) async throws -> BackupRecord {
        var name = newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")

        guard !name.isEmpty else {
            throw RenameError.invalidName
        }

        // Без явного расширения подставляем расширение текущего
        // имени — иначе QuickLook/провайдеры могут не распознать тип.
        if !name.contains("."),
           let ext = (record.fileName as NSString).pathExtension.nilIfEmpty {
            name += ".\(ext)"
        }

        guard name != record.fileName else { return record }

        let versions = try backupRepository.fetchVersions(for: record.id)
        let targetRepository = repository(for: record)

        var firstFailure: Error?
        for version in versions where !version.cloudObjectID.isEmpty {
            do {
                let renamed = try await targetRepository.renameFile(
                    id: version.cloudObjectID,
                    name: name
                )
                // У Dropbox id — это путь: после переименования он
                // меняется, сохраняем новый id в метаданные версии.
                if renamed.id != version.cloudObjectID {
                    var updated = version
                    updated.cloudObjectID = renamed.id
                    try backupRepository.updateVersion(updated)
                }
            } catch CloudStorageError.notFound {
                continue
            } catch CloudStorageError.notImplemented {
                continue
            } catch {
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }

        if let firstFailure {
            throw RenameError.cloudRenameFailed(
                firstFailure.localizedDescription
            )
        }

        var updatedRecord = record
        updatedRecord.fileName = name
        updatedRecord.updatedAt = Date()
        try backupRepository.saveRecord(updatedRecord)
        return updatedRecord
    }

    public enum RenameError: LocalizedError {
        case invalidName
        case cloudRenameFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Введите имя файла."
            case .cloudRenameFailed(let message):
                return "Не удалось переименовать файл в облаке: \(message)"
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
