import Foundation

/// Прямая ссылка для потокового воспроизведения медиафайла.
/// `headers` нужны провайдерам с авторизацией (Google Drive `alt=media`).
struct CloudMediaStream: Equatable {
    let url: URL
    /// HTTP-заголовки для `AVURLAsset` (например, Authorization).
    let headers: [String: String]
}
