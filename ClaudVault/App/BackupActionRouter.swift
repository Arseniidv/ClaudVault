import Foundation
import Observation

/// Действие создания резервной копии, запрошенное извне
/// (deep link из виджета).
enum BackupCreationRequest: Equatable {
    /// Открыть создание бэкапа с системным выбором файла.
    case pickFile
    /// Открыть камеру-сканер документов.
    case scanDocument
    /// Открыть выбор папки для загрузки в облако (macOS-меню «+»).
    case pickFolder
    /// Запросить создание новой папки в текущем облаке.
    case newFolder
    /// Запросить подключение облачного провайдера.
    case connectCloud(StorageProviderType)
}
@MainActor
@Observable
final class BackupActionRouter {
    var pendingRequest: BackupCreationRequest?

    func request(_ action: BackupCreationRequest) {
        pendingRequest = action
    }
}
