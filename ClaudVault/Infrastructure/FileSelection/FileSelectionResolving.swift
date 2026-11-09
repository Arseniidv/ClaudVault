import Foundation

/// Резолвер источника выделения файлов.
///
/// Реализации обязаны вернуть `nil`, если источник сейчас
/// не может предоставить выделение (нет разрешения, приложение
/// не поддерживает API и т.п.) — оркестратор переходит к
/// следующему источнику или fallback'у.
protocol FileSelectionResolving: Sendable {
    var source: SelectionSource { get }
    func resolve() async -> FileSelection?
}
