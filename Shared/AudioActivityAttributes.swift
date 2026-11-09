import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Атрибуты Live Activity «сейчас играет».
///
/// Файл компилируется в приложение и в расширение виджета через
/// synchronized group `Shared` — типы ActivityAttributes должны
/// быть доступны обеим сторонам: приложение запускает/обновляет
/// активность, виджет только рендерит её.
///
/// `trackID`/`providerName`/`fileName` — статичные (задаются
/// при старте активности и меняются только при смене трека),
/// `ContentState` — динамический (позиция, длительность, пауза).
/// Секретных данных (URL, токены) здесь нет — обложка передаётся
/// именем файла в общем контейнере App Group.
nonisolated struct AudioLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String?
        var isPlaying: Bool
        /// Позиция воспроизведения в секундах.
        var position: Double
        /// Длительность трека в секундах.
        var duration: Double
        /// Имя JPEG-файла обложки в App Group контейнере.
        var artworkFileName: String?
    }

    /// Стабильный id трека внутри очереди плеера.
    var trackID: String
    /// Провайдер: "googleDrive", "dropbox", "oneDrive", "local".
    var providerName: String
    /// Имя исходного аудиофайла.
    var fileName: String
}
#endif
