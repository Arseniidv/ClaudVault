import Foundation
import LocalAuthentication

final class BiometricAuthService {
    /// Доступна ли биометрия или пароль устройства для LAContext.
    func isAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Аутентификация биометрией с fallback на пароль устройства.
    /// Используется для блокировки приложения.
    func authenticateDeviceOwner(reason: String = "Разблокируйте CloudVault") async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        context.localizedFallbackTitle = "Ввести пароль"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw mapError(error)
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            throw mapError(error as NSError)
        }
    }

    /// Аутентификация для чувствительных операций (например, передача
    /// токенов на другое устройство): требует биометрию и НЕ
    /// предлагает пароль устройства, если биометрия настроена.
    /// Пароль допускается только когда биометрии нет вовсе или она
    /// в lockout — иначе операцию нельзя было бы выполнить вообще.
    func authenticateForSensitiveOperation(reason: String) async throws -> Bool {
        var context = LAContext()
        context.localizedCancelTitle = "Отмена"
        context.localizedFallbackTitle = "Ввести пароль"

        var probeError: NSError?
        let hasBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &probeError
        )

        if hasBiometrics {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
            } catch let error as NSError {
                // Lockout биометрии: без пароля устройства пользователь
                // вообще не сможет подтвердить операцию — разрешаем fallback.
                guard error.code == LAError.biometryLockout.rawValue else {
                    throw mapError(error)
                }
            }
        }

        context = LAContext()
        context.localizedCancelTitle = "Отмена"
        context.localizedFallbackTitle = "Ввести пароль"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            throw mapError(error as NSError)
        }
    }

    func authenticate() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            throw mapError(error)
        }
        do {
            let isAuthenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Разблокируйте CloudVault с помощью биометрии"
            )

            return isAuthenticated

        } catch {
            throw mapError(error as NSError)
        }
    }

    private func mapError(_ error: NSError?) -> Error {
        guard let error else {
            return BiometricAuthError.notAvailable
        }

        switch error.code {
        case LAError.biometryNotAvailable.rawValue:
            return BiometricAuthError.notAvailable

        case LAError.biometryNotEnrolled.rawValue:
            return BiometricAuthError.notEnrolled

        case LAError.biometryLockout.rawValue:
            return BiometricAuthError.lockout

        case LAError.userCancel.rawValue:
            return BiometricAuthError.userCancelled

        case LAError.systemCancel.rawValue:
            return BiometricAuthError.systemCancelled

        case LAError.appCancel.rawValue:
            return BiometricAuthError.appCancelled

        case LAError.authenticationFailed.rawValue:
            return BiometricAuthError.authenticationFailed

        default:
            return BiometricAuthError.unknown(error.localizedDescription)
        }
    }
}
enum BiometricAuthError: LocalizedError {

    case notAvailable
    case notEnrolled
    case lockout
    case userCancelled
    case systemCancelled
    case appCancelled
    case authenticationFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {

        case .notAvailable:
            return "Биометрическая аутентификация недоступна."

        case .notEnrolled:
            #if os(macOS)
            return "Touch ID не настроен на устройстве."
            #else
            return "Face ID не настроен на устройстве."
            #endif

        case .lockout:
            return "Биометрия заблокирована. Используйте пароль устройства для восстановления доступа."

        case .userCancelled:
            return "Проверка биометрии отменена пользователем."

        case .systemCancelled:
            return "Проверка биометрии прервана системой."

        case .appCancelled:
            return "Проверка биометрии прервана приложением."

        case .authenticationFailed:
            return "Не удалось подтвердить личность."

        case .unknown(let message):
            return "Ошибка биометрии: \(message)"
        }
    }
}
