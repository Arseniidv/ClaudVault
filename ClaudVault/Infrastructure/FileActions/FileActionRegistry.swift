import Foundation
import ClaudVaultDomain

/// Реестр обработчиков действий Radial Menu.
/// Заменяет разросшийся `switch` в UI: действия регистрируются
/// при старте и оцениваются/выполняются диспетчером.
@MainActor
final class FileActionRegistry {

    private var handlers: [FileActionKind: any FileActionHandling] = [:]

    func register(_ handler: any FileActionHandling) {
        handlers[handler.kind] = handler
    }

    func handler(for kind: FileActionKind) -> (any FileActionHandling)? {
        handlers[kind]
    }

    /// Оценивает все действия в фиксированном порядке
    /// `FileActionKind.allCases`.
    func evaluateAll(
        selection: FileSelection,
        context: FileActionContext
    ) async -> [FileActionDescriptor] {
        var descriptors: [FileActionDescriptor] = []
        for kind in FileActionKind.allCases {
            guard let handler = handlers[kind] else { continue }
            descriptors.append(
                await handler.evaluate(
                    selection: selection,
                    context: context
                )
            )
        }
        return descriptors
    }

    func perform(
        kind: FileActionKind,
        selection: FileSelection,
        context: FileActionContext,
        provider: StorageProviderType?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> FileActionOutcome {
        guard let handler = handlers[kind] else {
            throw FileActionError.unknownAction(kind)
        }
        return try await handler.perform(
            selection: selection,
            context: context,
            provider: provider,
            progressHandler: progressHandler
        )
    }
}

enum FileActionError: LocalizedError {
    case unknownAction(FileActionKind)
    case providerRequired(FileActionKind)
    case noBackupRecords

    var errorDescription: String? {
        switch self {
        case .unknownAction(let kind):
            return "Действие «\(kind.title)» недоступно."
        case .providerRequired(let kind):
            return "Для действия «\(kind.title)» нужно выбрать облако."
        case .noBackupRecords:
            return "Для выбранных файлов нет резервных копий."
        }
    }
}
