import Foundation
import ClaudVaultDomain

/// Держатель идентификатора текущего пользователя CloudVault.
///
/// Единственный источник «кто сейчас вошёл» для инфраструктурного
/// слоя: Keychain-хранилища, провайдерские токен-сторы и
/// SwiftData-репозитории читают `ownerID` отсюда, чтобы данные
/// разных аккаунтов никогда не пересекались.
///
/// Значение — стабильный UUID, производный от Firebase UID
/// (`FirebaseAuthRepository.stableUUID`). Устанавливается
/// `UserSessionCoordinator` при каждой смене auth-состояния,
/// в том числе в `nil` при выходе.
///
/// Класс thread-safe (`NSLock`): его читают и `@MainActor`
/// менеджеры, и фоновые `ModelContext` репозиториев.
final class CurrentUserContext: @unchecked Sendable {
    nonisolated static let shared = CurrentUserContext()

    private let lock = NSLock()
    nonisolated(unsafe) private var _ownerID: String?

    private init() {}

    /// Идентификатор текущего пользователя; `nil` — сеанса нет.
    nonisolated var ownerID: String? {
        lock.lock()
        defer { lock.unlock() }
        return _ownerID
    }

    nonisolated func set(_ ownerID: String?) {
        lock.lock()
        _ownerID = ownerID
        lock.unlock()
    }
}
