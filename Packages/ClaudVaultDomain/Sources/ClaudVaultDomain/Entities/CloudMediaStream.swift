import Foundation

/// Прямая ссылка для потокового воспроизведения медиафайла.
/// `headers` нужны провайдерам с авторизацией (Google Drive `alt=media`).
public struct CloudMediaStream: Equatable {
    public let url: URL
    /// HTTP-заголовки для `AVURLAsset` (например, Authorization).
    public let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}
