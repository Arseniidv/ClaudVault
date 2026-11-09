import Foundation

/// Информация об одном файле для режима «Информация».
struct FileInspectionInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let sizeText: String?
    let modifiedText: String?
    /// Провайдер облака, где лежит последняя версия (nil — нет копии).
    let backupProviderName: String?
    let backupVersionsCount: Int
    let lastUploadText: String?
}

/// Результат выполнения действия. Часть действий меняет
/// содержимое панели (например, «Информация»), остальные
/// просто завершаются сообщением.
enum FileActionOutcome: Sendable {
    case completed(String)
    case showInformation([FileInspectionInfo])
}
