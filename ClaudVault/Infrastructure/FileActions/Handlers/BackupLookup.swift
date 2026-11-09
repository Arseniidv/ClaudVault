import Foundation

/// Общий поиск backup-записей для выделенных локальных файлов.
/// `sourceIdentifier` записи совпадает с `url.path` — то же
/// соглашение, что использует `CreateBackupViewModel`.
@MainActor
enum BackupLookup {

    struct Match {
        let file: SelectedFile
        let record: BackupRecord
        let versions: [BackupVersion]

        /// Последняя по времени загрузки версия.
        var latestVersion: BackupVersion? {
            versions.max(by: { $0.uploadedAt < $1.uploadedAt })
        }
    }

    /// Записи с хотя бы одной загруженной версией — только они
    /// имеют смысл для Download/Transfer.
    static func matches(
        in selection: FileSelection,
        repository: BackupMetadataRepository
    ) -> [Match] {
        selection.files.compactMap { file in
            guard let record = try? repository.fetchRecord(
                bySource: file.url.path
            ) else { return nil }
            let versions = (try? repository.fetchVersions(
                for: record.id
            )) ?? []
            guard !versions.isEmpty else { return nil }
            return Match(file: file, record: record, versions: versions)
        }
    }
}
