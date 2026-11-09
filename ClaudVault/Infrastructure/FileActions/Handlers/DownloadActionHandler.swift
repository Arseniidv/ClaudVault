import Foundation

/// Download: скачивает последнюю облачную версию каждого файла,
/// для которого существует backup-запись. Файлы без копий
/// пропускаются; если таких нет вообще — действие недоступно.
@MainActor
final class DownloadActionHandler: FileActionHandling {

    let kind: FileActionKind = .download

    func evaluate(
        selection: FileSelection,
        context: FileActionContext
    ) async -> FileActionDescriptor {
        let matches = BackupLookup.matches(
            in: selection,
            repository: context.backupMetadataRepository
        )
        guard !matches.isEmpty else {
            return FileActionDescriptor(
                kind: kind, isEnabled: false,
                statusText: "Нет резервных копий"
            )
        }
        return FileActionDescriptor(
            kind: kind, isEnabled: true, statusText: nil
        )
    }

    func perform(
        selection: FileSelection,
        context: FileActionContext,
        provider: StorageProviderType?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> FileActionOutcome {
        let matches = BackupLookup.matches(
            in: selection,
            repository: context.backupMetadataRepository
        )
        guard !matches.isEmpty else {
            throw FileActionError.noBackupRecords
        }

        var downloaded = 0
        var firstError: Error?
        let total = max(matches.count, 1)

        for (index, match) in matches.enumerated() {
            try Task.checkCancellation()
            let provider = match.record.storageProvider
            guard let repository = context.repositories[provider] else {
                if firstError == nil {
                    firstError = CloudStorageError.operationFailed(
                        "Облако \(provider.name) недоступно."
                    )
                }
                continue
            }
            guard let version = match.latestVersion else { continue }

            do {
                let destination = uniqueDestination(
                    for: match.file.name,
                    in: context.downloadsDirectory
                )
                try await repository.downloadFile(
                    id: version.cloudObjectID,
                    to: destination
                ) { fraction in
                    let overall = (Double(index) + fraction)
                        / Double(total)
                    progressHandler(min(max(overall, 0), 1))
                }
                downloaded += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if downloaded == 0, let firstError { throw firstError }
        if let firstError {
            return .completed(
                "Скачано \(downloaded) из \(matches.count). "
                + "Ошибка: \(firstError.localizedDescription)"
            )
        }
        return .completed(
            "Скачано файлов: \(downloaded) в «Загрузки»."
        )
    }

    /// Уникальное имя в ~/Downloads: при коллизии добавляет
    /// « (2)», « (3)» и т.д. перед расширением.
    private func uniqueDestination(
        for name: String,
        in directory: URL
    ) -> URL {
        var candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path)
        else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        repeat {
            let suffix = ext.isEmpty ? " (\(counter))" : " (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(base + suffix)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }
}
