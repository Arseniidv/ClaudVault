import Foundation

/// Аудиотрек в очереди `AudioPlayerService`.
///
/// `source` описывает, откуда плеер получит байты:
/// - `.cloudFile` — файл в облачном хранилище; URL и заголовки
///   авторизации резолвятся лениво через `AudioSourceResolver`
///   в момент воспроизведения (временные ссылки не хранятся
///   в очереди и не попадают в виджет).
/// - `.localFile` — уже скачанная локальная копия.
/// - `.resolvedStream` — готовый `CloudMediaStream`
///   (например, полученный при открытии предпросмотра).
struct AudioTrack: Identifiable, Equatable {

    enum Source: Equatable {
        /// Облачный файл: провайдер + метаданные.
        /// `CloudFile` хранится целиком — `id` может быть
        /// «путём» у Dropbox, поэтому для кэша используется
        /// хэш, а не сам id.
        case cloudFile(CloudFile, StorageProviderType)
        /// Локальный файл (кэш, временная копия, файл пользователя).
        case localFile(URL)
        /// Уже разрешённый потоковый дескриптор.
        case resolvedStream(CloudMediaStream)
    }

    /// Стабильный идентификатор: "provider|fileID" или UUID
    /// для локальных файлов.
    let id: String
    /// Отображаемое название (метаданные трека или имя файла).
    var title: String
    var artist: String?
    var album: String?
    /// Имя исходного файла — fallback для title.
    let fileName: String
    /// Провайдер для отображения и резолва.
    let provider: StorageProviderType
    /// Длительность, если известна заранее (метаданные облака).
    var knownDuration: TimeInterval?
    let source: Source
    /// JPEG-данные обложки (заполняются после загрузки метаданных).
    var artworkJPEG: Data?

    /// Текущая длительность: сначала метаданные облака,
    /// затем длительность из AVAsset.
    var duration: TimeInterval {
        knownDuration ?? 0
    }

    /// Расширение имени файла без точки в нижнем регистре.
    var fileExtension: String {
        fileName.split(separator: ".").last?
            .lowercased() ?? ""
    }
}

extension AudioTrack {

    /// Трек из облачного файла. `title`/`artist` берутся из
    /// метаданных, если провайдер их отдал, иначе — из имени.
    init(
        file: CloudFile,
        provider: StorageProviderType,
        stream: CloudMediaStream? = nil
    ) {
        let baseID = "\(provider.rawValue)|\(file.id)"
        self.id = baseID
        self.fileName = file.name
        self.provider = provider
        self.knownDuration = file.duration
        if let stream {
            self.source = .resolvedStream(stream)
        } else {
            self.source = .cloudFile(file, provider)
        }

        // Имя файла без расширения — базовое название.
        let stem = file.name
            .split(separator: ".")
            .dropLast()
            .joined(separator: ".")
        self.title = stem.isEmpty ? file.name : stem
        self.artist = nil
        self.album = nil
        self.artworkJPEG = nil
    }

    /// Трек из локального файла (кэш/временная копия).
    init(localFile url: URL, provider: StorageProviderType = .local) {
        let fileName = url.lastPathComponent
        self.id = "local|\(fileName)|\(url.path)"
        self.fileName = fileName
        self.provider = provider
        self.knownDuration = nil
        self.source = .localFile(url)

        let stem = fileName
            .split(separator: ".")
            .dropLast()
            .joined(separator: ".")
        self.title = stem.isEmpty ? fileName : stem
        self.artist = nil
        self.album = nil
        self.artworkJPEG = nil
    }
}
