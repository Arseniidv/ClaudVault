import Foundation

/// Подключённый аккаунт облачного хранилища.
/// Не содержит токенов: токены запрашиваются у реализации репозитория.
struct CloudStorageAccount: Identifiable, Equatable {
    let id: String
    let email: String
    let displayName: String?
}
