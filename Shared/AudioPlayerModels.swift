import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Режим повтора очереди воспроизведения.
enum AudioRepeatMode: String, Codable, CaseIterable {
    /// После последнего трека воспроизведение останавливается.
    case off
    /// Текущий трек повторяется бесконечно.
    case one
    /// По окончании очереди переход к первому треку.
    case all

    var systemImage: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

/// Безопасный снимок аудиотрека для App Group.
///
/// Сознательно НЕ содержит URL, заголовки авторизации и токены:
/// виджет и Live Activity работают в других процессах и не должны
/// получать доступ к приватным ссылкам провайдеров. Виджет
/// отображает только метаданные, а команды управления передаёт
/// через `AudioCommandBus`.
struct WidgetAudioTrack: Codable, Equatable {
    /// Стабильный идентификатор трека внутри очереди.
    var id: String
    var title: String
    var artist: String?
    var album: String?
    /// Провайдер, из которого играет трек ("googleDrive", ...).
    var providerName: String
    /// Имя исходного файла в облаке.
    var fileName: String
    /// Длительность в секундах (0 — неизвестна).
    var duration: Double
    /// Позиция воспроизведения на момент `updatedAt`.
    var position: Double
    var isPlaying: Bool
    var isLoading: Bool
    var repeatMode: String
    var shuffleEnabled: Bool
    var artworkFileName: String?
    var queueIndex: Int
    var queueCount: Int
    var hasNext: Bool
    var hasPrevious: Bool
    /// Момент, на который актуальны `position`/`isPlaying`.
    var updatedAt: Date
}

/// Полный снимок состояния плеера в App Group `UserDefaults`.
struct AudioPlayerSnapshot: Codable, Equatable {
    var track: WidgetAudioTrack?
    var volume: Double
    /// Последняя ошибка воспроизведения (если была).
    var errorMessage: String?
    var updatedAt: Date
}

/// Константы канала обмена аудиоплеером между приложением
/// и расширением виджета. Значения общие для обоих таргетов.
enum AudioWidgetConfig {
    /// `kind` виджета плеера в `CloudVaultWidgetBundle`.
    nonisolated static let widgetKind = "AudioPlayerWidget"

    nonisolated static let snapshotKey = "latest_audio_player_snapshot"

    /// Darwin-имя уведомления о команде управления.
    /// Оба процесса используют один App Group.
    nonisolated static let commandNotificationName =
        "group.com.Arseniidv.ClaudVault.audio.command" as CFString
}

/// Хранилище обложек треков в общем контейнере App Group.
///
/// Обложка — JPEG-файл `AudioArtwork/<fileName>` внутри
/// `group.com.Arseniidv.ClaudVault`; в снимке передаётся только
/// имя файла, поэтому мегабайты изображений не гоняются
/// через `UserDefaults`.
enum AudioArtworkStore {

    static let directoryName = "AudioArtwork"

    static var directoryURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.appGroupID)
        else { return nil }
        let dir = container.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Сохраняет JPEG-данные обложки и возвращает имя файла
    /// для включения в `WidgetAudioTrack.artworkFileName`.
    /// При nil-входе возвращает nil.
    @discardableResult
    static func save(_ data: Data?, for trackID: String) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let safeID = trackID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let fileName = "\(safeID).jpg"
        guard let dir = directoryURL else { return nil }
        try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    static func url(for fileName: String) -> URL? {
        directoryURL?.appendingPathComponent(fileName)
    }

    /// Загружает обложку как SwiftUI `Image` (UIImage/NSImage
    /// в зависимости от платформы). Файл отсутствует → nil.
    static func image(fileName: String?) -> Image? {
        guard let fileName,
              let url = url(for: fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    /// Удаляет файл обложки (при очистке очереди/выходе).
    static func remove(fileName: String?) {
        guard let fileName, let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
