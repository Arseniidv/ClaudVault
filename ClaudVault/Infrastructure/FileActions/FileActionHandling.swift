import Foundation
import ClaudVaultDomain

/// Обработчик одного действия Radial Menu.
///
/// Реализация обязана использовать существующие Use Cases
/// и репозитории — Radial Menu не дублирует облачную логику.
@MainActor
protocol FileActionHandling: AnyObject {
    var kind: FileActionKind { get }

    /// Доступно ли действие для данного выделения.
    /// `isEnabled == false` + `statusText` объясняет причину.
    func evaluate(
        selection: FileSelection,
        context: FileActionContext
    ) async -> FileActionDescriptor

    /// Выполняет действие. `provider` передаётся только для
    /// действий с `requiresProvider == true`.
    /// `progressHandler` получает общий прогресс 0...1 —
    /// обработчики без длительных операций его игнорируют.
    func perform(
        selection: FileSelection,
        context: FileActionContext,
        provider: StorageProviderType?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> FileActionOutcome
}
