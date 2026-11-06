import Foundation

/// Ошибки операций с облачным хранилищем.
/// SDK-специфичные ошибки маппятся в Data/Infrastructure,
/// поэтому Presentation видит только этот тип.
enum CloudStorageError: LocalizedError, Equatable {
    case notConfigured
    case cancelled
    case notConnected
    case permissionDenied
    case noPresentingWindow
    case unauthorized
    case forbidden(String)
    case notFound
    case rateLimited
    case requestFailed(statusCode: Int, message: String)
    case network(String)
    case invalidResponse
    case operationFailed(String)
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Облачное хранилище не настроено: отсутствует клиентский ID (Info.plist)."
        case .cancelled:
            return "Операция отменена."
        case .notConnected:
            return "Аккаунт Google не подключён."
        case .permissionDenied:
            return "Не предоставлен доступ к Google Drive."
        case .noPresentingWindow:
            return "Не удалось показать окно авторизации."
        case .unauthorized:
            return "Сессия Google истекла. Подключите аккаунт заново."
        case .forbidden(let message):
            return "Недостаточно прав для операции: \(message)"
        case .notFound:
            return "Файл не найден или был удалён."
        case .rateLimited:
            return "Превышен лимит запросов к Google Drive. Попробуйте позже."
        case .requestFailed(let statusCode, let message):
            return "Ошибка Google Drive (\(statusCode)): \(message)"
        case .network(let message):
            return "Сетевая ошибка: \(message)"
        case .invalidResponse:
            return "Google Drive вернул некорректный ответ."
        case .operationFailed(let message):
            return "Операция не выполнена: \(message)"
        case .notImplemented:
            return "Не реализовано"
        }
    }
}
