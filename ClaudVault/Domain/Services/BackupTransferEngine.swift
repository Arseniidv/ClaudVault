import Foundation

/// Шов для chunked-движка передач (загрузка и cloud-to-cloud
/// перенос). iOS-реализация — `TransferEngine` в Infrastructure;
/// Android получит свою реализацию поверх тех же протоколов.
@MainActor
public protocol BackupTransferEngine: AnyObject {
    /// Вызывается при изменении прогресса активной передачи (0...1).
    var onProgress: (@Sendable (Double) -> Void)? { get set }

    /// Копирует файл из одного облака в другое чанками с
    /// журналированием и верификацией. Бросает `.notImplemented`,
    /// если провайдеры не поддерживают chunked-передачу —
    /// вызывающий код использует fallback через временный файл.
    func transferFile(
        _ file: CloudFile,
        from sourceProvider: String,
        source: any CloudStorageRepository,
        to targetProvider: String,
        target: any CloudStorageRepository,
        targetParentID: String?,
        move: Bool
    ) async throws -> CloudFile
}
