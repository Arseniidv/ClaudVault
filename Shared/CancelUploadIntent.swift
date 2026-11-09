import AppIntents
import Foundation

/// Кнопка «Отменить» в Live Activity загрузки файла.
///
/// Выполняется без открытия приложения: помечает `UploadSession`
/// отменённой в `UploadCancellation` — ближайшая граница чанка
/// в цикле загрузки приложения остановит передачу.
struct CancelUploadIntent: AppIntent {
    static var title: LocalizedStringResource = "Отменить загрузку"
    static var description = IntentDescription(
        "Отменяет текущую загрузку файла в облачное хранилище."
    )

    /// Кнопка только в Live Activity — в Shortcuts не показываем.
    static var isDiscoverable: Bool { false }
    /// Отмена не должна выводить пользователя в приложение.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Сессия загрузки")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: sessionID) {
            UploadCancellation.markCancelled(id)
        }
        return .result()
    }
}
