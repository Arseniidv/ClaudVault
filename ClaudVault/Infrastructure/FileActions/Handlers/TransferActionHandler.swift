import Foundation

/// Transfer: перемещает все облачные версии backup-записей
/// выделенных файлов в выбранное облако через
/// `TransferBackupToProviderUseCase` (move == true —
/// исходные объекты удаляются после верификации).
@MainActor
final class TransferActionHandler: FileActionHandling {

    let kind: FileActionKind = .transfer

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
        guard let provider,
              context.supportedProviders.contains(provider),
              provider != .local, provider != .iCloud,
              provider != .unknown else {
            throw FileActionError.providerRequired(kind)
        }

        let matches = BackupLookup.matches(
            in: selection,
            repository: context.backupMetadataRepository
        )
        guard !matches.isEmpty else {
            throw FileActionError.noBackupRecords
        }

        var transferred = 0
        var skipped = 0
        var firstError: Error?
        // Провайдеры и id старых облачных объектов — для
        // обновления списков файлов и «недавно открытых»
        // после перемещения.
        var affectedProviders = Set<StorageProviderType>()
        var removedCloudFileIDs: [StorageProviderType: Set<String>] = [:]

        for (index, match) in matches.enumerated() {
            try Task.checkCancellation()
            let sourceProvider = match.record.storageProvider
            guard sourceProvider != provider else {
                skipped += 1
                continue
            }
            do {
                try await context.transferBackupToProvider.execute(
                    record: match.record,
                    to: provider,
                    move: true
                ) { fraction in
                    let overall = (Double(index) + fraction)
                        / Double(matches.count)
                    progressHandler(min(max(overall, 0), 1))
                }
                transferred += 1
                affectedProviders.insert(sourceProvider)
                affectedProviders.insert(provider)
                removedCloudFileIDs[sourceProvider, default: []]
                    .formUnion(match.versions.map(\.cloudObjectID))
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        // Списки файлов в разделе «Хранилища» и кэш
        // листингов обновляем сразу — иначе перенесённый
        // файл «исчезает» из вида до ручного refresh.
        if !affectedProviders.isEmpty {
            await context.storagesViewModel?
                .refreshAfterExternalChange(
                    providers: Array(affectedProviders),
                    deletedCloudFileIDs: removedCloudFileIDs
                )
        }

        if transferred == 0 {
            if skipped > 0 {
                return .completed(
                    "Файлы уже находятся в \(provider.name)."
                )
            }
            if let firstError { throw firstError }
        }
        if let firstError {
            return .completed(
                "Перемещено \(transferred) из \(matches.count) "
                + "в \(provider.name). Ошибка: "
                + firstError.localizedDescription
            )
        }
        return .completed(
            "Перемещено файлов: \(transferred) в \(provider.name). "
            + "Копии в исходном облаке удалены."
        )
    }
}
