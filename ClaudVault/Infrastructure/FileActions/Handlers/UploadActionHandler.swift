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
        provider: StorageProviderType?
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

            for file in selection.files {
                try Task.checkCancellation()
                do {
                    _ = try await context.createBackupWithUpload.execute(
                        fileName: file.name,
                        sourceIdentifier: file.url.path,
                        fileURL: file.url,
                        parentFolderID: nil,
                        storageProvider: provider
                    ) { _ in }
                    succeeded += 1
                } catch {
                    if firstError == nil { firstError = error }
                }
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
