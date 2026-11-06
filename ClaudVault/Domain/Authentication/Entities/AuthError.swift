//
//  AuthError.swift
//  ClaudVault
//
//  Ошибки авторизации доменного уровня.
//  Конкретные ошибки SDK (например, Firebase) маппятся
//  в Data-слое, поэтому Domain не знает о них.
//

import Foundation

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case userNotFound
    case emailAlreadyInUse
    case weakPassword
    case networkUnavailable
    case tooManyRequests
    case operationNotAllowed
    case sessionExpired
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Неверный email или пароль."
        case .userNotFound:
            return "Пользователь с таким email не найден."
        case .emailAlreadyInUse:
            return "Аккаунт с таким email уже существует."
        case .weakPassword:
            return "Пароль слишком простой. Используйте минимум 6 символов."
        case .networkUnavailable:
            return "Нет подключения к сети. Проверьте соединение и повторите попытку."
        case .tooManyRequests:
            return "Слишком много попыток. Попробуйте позже."
        case .operationNotAllowed:
            return "Операция не разрешена. Обратитесь в поддержку."
        case .sessionExpired:
            return "Сессия истекла. Войдите снова."
        case .unknown(let message):
            return message
        }
    }
}
