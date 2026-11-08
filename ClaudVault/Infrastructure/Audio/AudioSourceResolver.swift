import Foundation
import CryptoKit

/// Разрешённый источник аудио для `AVURLAsset`:
/// URL + HTTP-заголовки авторизации (Google Drive `alt=media`).
struct ResolvedAudioSource: Equatable {
    let url: URL
    let headers: [String: String]
}

/// Резолвит `AudioTrack.Source` в конкретный URL актива.
///
/// Порядок для облачных файлов:
/// 1. Локальный кэш загрузок (`Caches/AudioCache`) — уже
///    скачанные файлы не запрашиваются повторно.
/// 2. `streamDescriptor` провайдера — потоковое воспроизведение
///    без полного скачивания (Dropbox temp link, Google
///    `alt=media` + Bearer).
/// 3. Полное скачивание в кэш — если провайдер не умеет
///    отдавать прямые ссылки.
///
/// Заголовки остаются внутри процесса приложения и никогда
/// не записываются в App Group / виджет / Live Activity.
final class AudioSourceResolver {

    private let repositories: [StorageProviderType: CloudStorageRepository]

    init(repositories: [StorageProviderType: CloudStorageRepository]) {
        self.repositories = repositories
    }

    /// Директория кэша аудио (создаётся лениво).
    static var cacheDirectory: URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Стабильный ключ кэша для облачного файла:
    /// хэш от "provider|fileID" — `id` Dropbox является путём
    /// и может содержать символы, недопустимые в имени файла.
    static func cacheKey(for file: CloudFile, provider: StorageProviderType) -> String {
        let raw = "\(provider.rawValue)|\(file.id)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func resolve(_ track: AudioTrack) async throws -> ResolvedAudioSource {
        switch track.source {
        case .localFile(let url):
            return ResolvedAudioSource(url: url, headers: [:])

        case .resolvedStream(let stream):
            return ResolvedAudioSource(
                url: stream.url,
                headers: stream.headers
            )

        case .cloudFile(let file, let provider):
            guard let repository = repositories[provider] else {
                throw CloudStorageError.notConnected
            }

            let cached = Self.cacheFileURL(
                for: file,
                provider: provider
            )

            // 1. Уже скачанная копия — играем её, не трогая сеть.
            if FileManager.default.fileExists(atPath: cached.path) {
                return ResolvedAudioSource(url: cached, headers: [:])
            }

            // 2. Прямой стриминг — основной путь для облака.
            if let stream = try? await repository.streamDescriptor(for: file) {
                return ResolvedAudioSource(
                    url: stream.url,
                    headers: stream.headers
                )
            }

            // 3. Провайдер не отдаёт ссылки — скачиваем в кэш
            //    и играем локально. Файл остаётся в кэше для
            //    повторных прослушиваний.
            try await repository.downloadFile(
                id: file.id,
                to: cached,
                progressHandler: nil
            )
            return ResolvedAudioSource(url: cached, headers: [:])
        }
    }

    /// Путь кэшированного файла. Расширение сохраняем от
    /// исходного имени — AVPlayer определяет формат по URL.
    private static func cacheFileURL(
        for file: CloudFile,
        provider: StorageProviderType
    ) -> URL {
        let key = cacheKey(for: file, provider: provider)
        var name = key
        if let ext = file.name.split(separator: ".").last,
           !ext.isEmpty {
            name += ".\(ext.lowercased())"
        }
        return cacheDirectory.appendingPathComponent(name)
    }
}
