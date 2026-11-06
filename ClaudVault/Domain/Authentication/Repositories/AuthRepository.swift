
import Foundation

protocol AuthRepository {
    func signIn(
        email: String,
        password: String
    ) async throws -> AuthUser

    func signUp(
        name: String,
        email: String,
        password: String
    ) async throws -> AuthUser

    func signOut() async throws

    func resetPassword(
        email: String
    ) async throws

    /// Отправляет письмо со ссылкой для входа/верификации email (passwordless).
    func sendEmailSignInLink(email: String) async throws

    /// Проверяет, что URL — ссылка входа через email.
    func isEmailSignInLink(_ url: URL) -> Bool

    /// Завершает вход по email-ссылке. Требует email, использованный при отправке.
    func completeEmailSignIn(email: String, link: URL) async throws -> AuthUser

    func getCurrentUser() async -> AuthUser?

    func authStateChanges() -> AsyncStream<AuthUser?>
}
