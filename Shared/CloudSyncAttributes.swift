import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Атрибуты Live Activity «синхронизация резервной копии».
///
/// Файл компилируется в приложение и в расширение виджета через
/// synchronized group `Shared` — типы ActivityAttributes должны
/// быть доступны обеим сторонам: приложение запускает/обновляет
/// активность, виджет только рендерит её.
///
/// `fileName` и `providerName` — статичные (задаются при старте),
/// `ContentState` — динамический (прогресс, скорость, статус).
struct CloudSyncAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Прогресс загрузки 0...1.
        var progress: Double
        /// Отформатированная скорость, например "4.5 MB/s".
        var currentSpeed: String
        /// Человекочитаемый статус: "Загрузка...", "Завершено" и т.п.
        var statusMessage: String
    }

    /// Имя загружаемого файла.
    var fileName: String
    /// Облачное хранилище: "Google Drive", "Dropbox", "OneDrive".
    var providerName: String
}
#endif
