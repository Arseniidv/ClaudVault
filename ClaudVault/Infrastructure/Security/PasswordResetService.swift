import Foundation
import FirebaseFunctions

enum PasswordResetServiceError: LocalizedError {
    /// Callable-функции не развёрнуты в Firebase-проекте.
    case functionNotDeployed

    var errorDescription: String? {
        switch self {
        case .functionNotDeployed:
            return "Сервис сброса пароля не развёрнут на сервере. Необходимо выполнить deploy Cloud Functions."
        }
    }
}

/// Сброс пароля через Gmail: Cloud Functions отправляют 6-значный код
/// на email через SMTP, а `confirmReset` устанавливает новый пароль
/// через Firebase Admin SDK. Не требует авторизации пользователя.
final class PasswordResetService {

    private let functions = Functions.functions()

    /// Шаг 1: отправляет код сброса на указанный email.
    /// Сервер не раскрывает, существует ли аккаунт.
    func requestCode(email: String) async throws {
        do {
            _ = try await functions
                .httpsCallable("requestPasswordResetCode")
                .call(["email": email])
        } catch let error as NSError
                    where error.domain == FunctionsErrorDomain
                    && error.code == FunctionsErrorCode.notFound.rawValue {
            throw PasswordResetServiceError.functionNotDeployed
        }
    }

    /// Шаг 2: проверяет код и устанавливает новый пароль.
    func confirmReset(
        email: String,
        code: String,
        newPassword: String
    ) async throws {
        do {
            _ = try await functions
                .httpsCallable("confirmPasswordReset")
                .call([
                    "email": email,
                    "code": code,
                    "newPassword": newPassword
                ])
        } catch let error as NSError
                    where error.domain == FunctionsErrorDomain
                    && error.code == FunctionsErrorCode.notFound.rawValue {
            throw PasswordResetServiceError.functionNotDeployed
        }
    }
}
