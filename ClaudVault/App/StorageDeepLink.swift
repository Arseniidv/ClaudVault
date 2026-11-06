import Foundation

/// Deep link из виджета хранилищ: `claudvault://storage/{provider}?email={email}`.
///
/// - `claudvault://storage` — просто открыть раздел «Хранилища».
/// - `claudvault://storage/googleDrive?email=…` — открыть раздел
///   и выбрать конкретный провайдер.
struct StorageDeepLink: Equatable {
    /// `StorageProviderType.rawValue`. nil — провайдер не указан.
    let provider: StorageProviderType?
    let email: String?

    /// Возвращает nil, если URL не относится к виджету хранилищ
    /// (другие `claudvault://` ссылки обрабатываются своими владельцами).
    static func parse(_ url: URL) -> StorageDeepLink? {
        guard url.scheme == "claudvault",
              url.host == "storage" else {
            return nil
        }

        let providerRaw = url.pathComponents.dropFirst().first
        let provider = providerRaw.flatMap(StorageProviderType.init(rawValue:))

        let email = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "email" })?
            .value

        return StorageDeepLink(provider: provider, email: email)
    }
}
