import Foundation

/// Upload: создаёт резервные копии выделенных файлов
/// через `CreateBackupWithUploadUseCase` — с дедупликацией
/// по SHA-256, UploadSession и журналом передач, как в
/// основном сценарии создания бэкапа.
@MainActor
final class UploadActionHandler: FileActionHandling {

    let kind: FileActionKind = .upload

    func evaluate(
        selection: FileSelection,
        context: FileActionContext
    ) async -> FileActionDescriptor {
        guard !selection.isEmpty else {
            return FileActionDescriptor(
                kind: kind, isEnabled: false,
                statusText: "Нет файлов"
            )
        }
        guard context.supportedProviders.contains(where: {
            context.repositories[$0] != nil
        }) else {
            return FileActionDescriptor(
                kind: kind, isEnabled: false,
                statusText: "Нет подключённых облаков"
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

        // Security-scoped доступ удерживаем на всю пачку.
        return try await SecurityScopedAccessManager().withAccess(
            to: selection.urls
        ) {
            var succeeded = 0
            var firstError: Error?
            let total = max(selection.files.count, 1)

            for (index, file) in selection.files.enumerated() {
                try Task.checkCancellation()
                do {
                    _ = try await context.createBackupWithUpload.execute(
                        fileName: file.name,
                        sourceIdentifier: file.url.path,
                        fileURL: file.url,
                        parentFolderID: nil,
                        storageProvider: provider
                    ) { fraction in
                        let overall = (Double(index) + fraction)
                            / Double(total)
                        progressHandler(min(max(overall, 0), 1))
                    }
                    succeeded += 1
                } catch {
                    if firstError == nil { firstError = error }
                }
            }

            // Новые облачные объекты появились в корне
            // провайдера — обновляем списки и кэш.
            if succeeded > 0 {
                await context.storagesViewModel?
                    .refreshAfterExternalChange(providers: [provider])
            }

            if succeeded == 0, let firstError { throw firstError }
            if let firstError {
                return .completed(
                    "Загружено \(succeeded) из \(selection.files.count). "
                    + "Ошибка: \(firstError.localizedDescription)"
                )
            }
            return .completed(
                "Загружено файлов: \(succeeded) "
                + "в \(provider.name)."
            )
        }
    }
}
