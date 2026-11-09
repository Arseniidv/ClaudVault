import Foundation

/// Подключённый аккаунт облачного хранилища.
/// Не содержит токенов: токены запрашиваются у реализации репозитория.
public struct CloudStorageAccount: Identifiable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String?

    public init(id: String, email: String, displayName: String?) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}
