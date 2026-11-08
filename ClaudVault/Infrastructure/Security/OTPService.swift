import Foundation
import FirebaseFunctions

enum OTPServiceError: LocalizedError {
    /// Callable-функция не развёрнута в Firebase-проекте.
    case functionNotDeployed
    /// Сервер не вернул срок действия доверенного окна.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .functionNotDeployed:
            return "Сервис подтверждения не развёрнут на сервере. Необходимо выполнить deploy Cloud Functions."
        case .invalidResponse:
            return "Некорректный ответ сервера подтверждения."
        }
    }
}

/// Сервис OTP-подтверждения через Firebase Cloud Functions.
/// Коды генерируются и проверяются на сервере, отправка — через SMTP.
final class OTPService {
    static let twoFactorEnabledKey = "twoFactorEnabled"
    private static let verifiedUntilKey = "otpVerifiedUntil"

    private let functions = Functions.functions()

    /// Ключ UserDefaults с учётом текущего пользователя CloudVault.
    /// Без этого 2FA-флаг и «доверенное окно» одного аккаунта
    /// наследовались бы следующим после logout/login — окно,
    /// открытое пользователем A, позволяло бы B подключать облака
    /// без OTP. При отсутствии владельца (до входа) используется
    /// легаси-ключ без суффикса.
    static func scopedKey(_ base: String) -> String {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return base
        }
        return "\(base).\(ownerID)"
    }

    // MARK: - 2FA flag

    var isTwoFactorEnabled: Bool {
        get {
            UserDefaults.standard.bool(
                forKey: Self.scopedKey(Self.twoFactorEnabledKey)
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: Self.scopedKey(Self.twoFactorEnabledKey)
            )
        }
    }

    // MARK: - Trust window

    /// `true`, если пользователь недавно прошёл OTP-проверку
    /// (сервер подтвердил код, клиент хранит срок действия окна).
    var isRecentlyVerified: Bool {
        let until = UserDefaults.standard.double(
            forKey: Self.scopedKey(Self.verifiedUntilKey)
        )
        return until > Date().timeIntervalSince1970
    }

    // MARK: - Cloud calls

    /// Запрашивает 6-значный код — сервер отправит его на email аккаунта.
    func requestCode() async throws {
        do {
            _ = try await functions
                .httpsCallable("requestEmailOtp")
                .call()
        } catch let error as NSError
                    where error.domain == FunctionsErrorDomain
                    && error.code == FunctionsErrorCode.notFound.rawValue {
            throw OTPServiceError.functionNotDeployed
        }
    }

    /// Проверяет код. При успехе открывает доверенное окно (~15 минут).
    func verifyCode(_ code: String) async throws {
        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable("verifyEmailOtp")
                .call(["code": code])
        } catch let error as NSError
                    where error.domain == FunctionsErrorDomain
                    && error.code == FunctionsErrorCode.notFound.rawValue {
            throw OTPServiceError.functionNotDeployed
        }

        let data = result.data as? [String: Any]
        // Без валидного срока от сервера доверенное окно не открываем —
        // подставлять «примерные 15 минут» на клиенте нельзя.
        guard let validUntil = (data?["validUntil"] as? NSNumber)?.doubleValue else {
            throw OTPServiceError.invalidResponse
        }
        UserDefaults.standard.set(
            validUntil,
            forKey: Self.scopedKey(Self.verifiedUntilKey)
        )
    }
}
