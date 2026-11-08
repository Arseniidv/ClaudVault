import Foundation

/// Information: собирает свойства файлов и статус резервной
/// копии (провайдер, число версий, дата последней загрузки).
@MainActor
final class InformationActionHandler: FileActionHandling {

    let kind: FileActionKind = .information

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    func evaluate(
        selection: FileSelection,
        context: FileActionContext
    ) async -> FileActionDescriptor {
        FileActionDescriptor(
            kind: kind,
            isEnabled: !selection.isEmpty,
            statusText: selection.isEmpty ? "Нет файлов" : nil
        )
    }

    func perform(
        selection: FileSelection,
        context: FileActionContext,
        provider: StorageProviderType?
    ) async throws -> FileActionOutcome {
        guard !selection.isEmpty else {
            throw FileActionError.noBackupRecords
        }

        let matches = Dictionary(
            uniqueKeysWithValues: BackupLookup.matches(
                in: selection,
                repository: context.backupMetadataRepository
            ).map { ($0.file.id, $0) }
        )

        let infos = selection.files.map { file -> FileInspectionInfo in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: file.url.path
            )
            let size = (attributes?[.size] as? NSNumber)?.int64Value
            let modified = attributes?[.modificationDate] as? Date

            let match = matches[file.id]
            let latest = match?.latestVersion

            return FileInspectionInfo(
                id: file.id,
                name: file.name,
                path: file.url.path,
                sizeText: size.map {
                    Self.byteFormatter.string(fromByteCount: $0)
                },
                modifiedText: modified.map {
                    Self.dateFormatter.string(from: $0)
                },
                backupProviderName: match?.record.storageProvider
                    .name,
                backupVersionsCount: match?.versions.count ?? 0,
                lastUploadText: latest.map {
                    Self.dateFormatter.string(from: $0.uploadedAt)
                }
            )
        }

        return .showInformation(infos)
    }
}
