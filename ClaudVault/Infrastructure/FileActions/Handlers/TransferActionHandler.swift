import Foundation

/// Transfer: копирует все облачные версии backup-записей
/// выделенных файлов в выбранное облако через
/// `TransferBackupToProviderUseCase` (move == false —
/// исходные объекты не удаляются).
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
        provider: StorageProviderType?
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

        for match in matches {
            try Task.checkCancellation()
            guard match.record.storageProvider != provider else {
                skipped += 1
                continue
            }
            do {
                try await context.transferBackupToProvider.execute(
                    record: match.record,
                    to: provider,
                    move: false
                ) { _ in }
                transferred += 1
            } catch {
                if firstError == nil { firstError = error }
            }
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
                "Перенесено \(transferred) из \(matches.count). "
                + "Ошибка: \(firstError.localizedDescription)"
            )
        }
        return .completed(
            "Перенесено файлов: \(transferred) в \(provider.name)."
        )
    }
}
