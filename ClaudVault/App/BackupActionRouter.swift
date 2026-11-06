import Foundation
import Observation

/// Действие создания резервной копии, запрошенное извне
/// (deep link из виджета).
enum BackupCreationRequest: Equatable {
    /// Открыть создание бэкапа с системным выбором файла.
    case pickFile
    /// Открыть камеру-сканер документов.
    case scanDocument
}

/// Передаёт запрос на создание бэкапа из `RootView` (обработчик URL)
/// в `BackupListView`, который владеет sheet'ами создания бэкапа
/// и сканера.
///
/// Запрос не сбрасывается при чтении: если пользователь не авторизован
/// и `BackupListView` ещё не существует, запрос дождётся его появления
/// после входа в аккаунт.
@MainActor
@Observable
final class BackupActionRouter {
    var pendingRequest: BackupCreationRequest?

    func request(_ action: BackupCreationRequest) {
        pendingRequest = action
    }
}
