import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// QR Guard — перенос сессий облачных провайдеров между устройствами.
///
/// Поток (аналог Steam Guard):
///  1. Новое устройство (`beginGeneratorSession`) генерирует пару
///     `Curve25519.KeyAgreement`, публикует открытый ключ в Firestore
///     `qr_verification_sessions/{id}` и показывает QR
///     `claudvault://verify?session=<id>`.
///  2. Доверенное устройство сканирует QR, забирает открытый ключ,
///     генерирует свою пару, выводит общий секрет (ECDH),
///     шифрует JSON с токенами AES.GCM и пишет
///     `trustedPublicKey` + `encryptedPayload` в тот же документ.
///  3. Новое устройство получает обновление документа, выводит тот же
///     общий секрет, расшифровывает пакет, раскладывает токены
///     по Keychain и удаляет временный документ.
@MainActor
final class QRVerificationService {

    /// URL-схема, кодируемая в QR-коде.
    static let urlScheme = "claudvault"
    static let urlHost = "verify"
    /// Время жизни сессии переноса.
    static let sessionLifetime: TimeInterval = 10 * 60

    /// Общий контекст HKDF — одинаков на обоих устройствах.
    private static let hkdfSharedInfo = Data("ClaudVault.DeviceTransfer.v1".utf8)
    /// Таймаут обращений к Firestore: запись/чтение без серверного
    /// подтверждения не должна вешать UI бесконечно.
    private static let backendTimeout: TimeInterval = 15

    private let firestore: Firestore
    private let collectionName = "qr_verification_sessions"

    /// Приватный ключ активной сессии генератора (новое устройство).
    /// Хранится только в памяти — на диск не пишется.
    private var pendingGeneratorKey: Curve25519.KeyAgreement.PrivateKey?
    private var pendingSessionID: String?
    private var completionContinuation: CheckedContinuation<CloudTokenPayload, Error>?
    private var activeListener: ListenerRegistration?
    private var timeoutTask: Task<Void, Never>?

    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    // MARK: - Types

    /// Информация о сессии для доверенного устройства (сканер).
    struct ScannerSessionInfo {
        let sessionID: String
        let ownerUid: String
        let ownerEmail: String?
        let createdAt: Date?
        let deviceBPublicKey: Curve25519.KeyAgreement.PublicKey
    }

    // MARK: - Generator (новое устройство)

    /// Создаёт сессию верификации и возвращает URL для QR-кода.
    /// Требуется авторизация в Firebase — документ привязывается к uid.
    func beginGeneratorSession() async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DeviceTransferError.notAuthenticated
        }

        cancelGeneratorSession()

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let sessionID = UUID().uuidString
        let publicKeyB64 = privateKey.publicKey.rawRepresentation
            .base64EncodedString()

        let ownerEmail = Auth.auth().currentUser?.email ?? ""

        do {
            try await withBackendTimeout {
                try await self.sessionDocument(sessionID).setData([
                    "ownerUid": uid,
                    "ownerEmail": ownerEmail,
                    "deviceBPublicKey": publicKeyB64,
                    "status": "pending",
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(
                        date: Date().addingTimeInterval(Self.sessionLifetime)
                    )
                ])
            }
        } catch DeviceTransferError.backendUnavailable {
            // Запись могла уйти на сервер с опозданием —
            // удаление встанет в очередь после setData.
            sessionDocument(sessionID).delete { _ in }
            throw DeviceTransferError.backendUnavailable
        }

        pendingGeneratorKey = privateKey
        pendingSessionID = sessionID

        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.queryItems = [
            URLQueryItem(name: "session", value: sessionID)
        ]
        guard let url = components.url else {
            throw DeviceTransferError.invalidSessionData
        }
        return url
    }

    /// Ждёт, пока доверенное устройство не пришлёт зашифрованный пакет.
    /// Возвращает расшифрованный `CloudTokenPayload`.
    /// Сессию и слушатель нужно завершить `cancelGeneratorSession()`.
    func awaitTransferredPayload() async throws -> CloudTokenPayload {
        guard let sessionID = pendingSessionID,
              let privateKey = pendingGeneratorKey else {
            throw DeviceTransferError.noActiveSession
        }

        return try await withCheckedThrowingContinuation { continuation in
            completionContinuation = continuation
            activeListener = sessionDocument(sessionID)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor [weak self] in
                        self?.handleGeneratorSnapshot(
                            snapshot: snapshot,
                            error: error,
                            privateKey: privateKey,
                            sessionID: sessionID
                        )
                    }
                }

            // Страховка от вечного ожидания: expiresAt в документе
            // не генерирует событие листенера, поэтому таймаут — на клиенте.
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .seconds(Self.sessionLifetime + 30)
                )
                guard !Task.isCancelled, let self else { return }
                let expiredID = self.pendingSessionID
                self.finishGenerator(throwing: DeviceTransferError.sessionExpired)
                if let expiredID {
                    try? await self.sessionDocument(expiredID).delete()
                }
            }
        }
    }

    /// Отменяет активную сессию генератора: удаляет слушатель
    /// и временный документ из Firestore.
    func cancelGeneratorSession() {
        activeListener?.remove()
        activeListener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completionContinuation?.resume(
            throwing: DeviceTransferError.sessionCancelled
        )
        completionContinuation = nil
        pendingGeneratorKey = nil

        if let sessionID = pendingSessionID {
            pendingSessionID = nil
            sessionDocument(sessionID).delete()
        }
    }

    private func handleGeneratorSnapshot(
        snapshot: DocumentSnapshot?,
        error: Error?,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        sessionID: String
    ) {
        if let error {
            finishGenerator(throwing: error)
            return
        }
        guard let data = snapshot?.data() else { return }

        guard data["status"] as? String == "approved",
              let trustedPublicKeyB64 = data["trustedPublicKey"] as? String,
              let encryptedPayload = data["encryptedPayload"] as? String else {
            return
        }

        do {
            let payload = try Self.decryptPayload(
                encryptedPayload: encryptedPayload,
                trustedPublicKeyBase64: trustedPublicKeyB64,
                privateKey: privateKey,
                sessionID: sessionID
            )
            finishGenerator(returning: payload)
            // Временный документ больше не нужен.
            sessionDocument(sessionID).delete()
        } catch {
            finishGenerator(throwing: error)
            // Пакет не расшифровался — approved-документ с чужим
            // зашифрованным payload не должен оставаться в Firestore.
            sessionDocument(sessionID).delete()
        }
    }

    private func finishGenerator(
        returning payload: CloudTokenPayload? = nil,
        throwing error: Error? = nil
    ) {
        activeListener?.remove()
        activeListener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation = completionContinuation {
            completionContinuation = nil
            if let payload {
                continuation.resume(returning: payload)
            } else {
                continuation.resume(
                    throwing: error ?? DeviceTransferError.decryptionFailed
                )
            }
        }
        pendingGeneratorKey = nil
        pendingSessionID = nil
    }

    // MARK: - Scanner (доверенное устройство)

    /// Извлекает session id из QR-ссылки вида
    /// `claudvault://verify?session=<id>` или из «голого» UUID.
    static func sessionID(from scannedValue: String) -> String? {
        let trimmed = scannedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.scheme == urlScheme,
           url.host == urlHost,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let session = components.queryItems?
               .first(where: { $0.name == "session" })?.value,
           !session.isEmpty {
            return session
        }

        // Разрешаем ввод голого UUID сессии.
        if UUID(uuidString: trimmed) != nil {
            return trimmed
        }
        return nil
    }

    /// Загружает сессию для сканера и проверяет, что она принадлежит
    /// текущему Firebase-аккаунту и не истекла.
    func scannerSessionInfo(
        for sessionID: String
    ) async throws -> ScannerSessionInfo {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DeviceTransferError.notAuthenticated
        }

        let snapshot = try await withBackendTimeout {
            try await self.sessionDocument(sessionID).getDocument()
        }
        guard let data = snapshot.data() else {
            throw DeviceTransferError.sessionNotFound
        }
        guard data["ownerUid"] as? String == uid else {
            throw DeviceTransferError.notSessionOwner
        }
        if let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(),
           expiresAt < Date() {
            throw DeviceTransferError.sessionExpired
        }
        guard data["status"] as? String == "pending",
              let publicKeyB64 = data["deviceBPublicKey"] as? String,
              let publicKeyData = Data(base64Encoded: publicKeyB64),
              let publicKey = try? Curve25519.KeyAgreement.PublicKey(
                  rawRepresentation: publicKeyData
              ) else {
            throw DeviceTransferError.invalidSessionData
        }

        return ScannerSessionInfo(
            sessionID: sessionID,
            ownerUid: uid,
            ownerEmail: data["ownerEmail"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            deviceBPublicKey: publicKey
        )
    }

    /// Шифрует пакет токенов ключом, общим для обоих устройств
    /// (ECDH: наша приватная пара + открытый ключ нового устройства)
    /// и передаёт в Firestore через Cloud Function.
    func sendPayload(
        _ payload: CloudTokenPayload,
        to info: ScannerSessionInfo
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(payload)

        let ownKey = Curve25519.KeyAgreement.PrivateKey()
        let sealedBox = try Self.encryptPayload(
            json: json,
            ownPrivateKey: ownKey,
            deviceBPublicKey: info.deviceBPublicKey,
            sessionID: info.sessionID
        )

        guard let combined = sealedBox.combined else {
            throw DeviceTransferError.encryptionFailed
        }

        // Запись approved-пакета выполняет только Cloud Function:
        // Firestore Rules запрещают клиентский update этой коллекции,
        // поэтому подмена/гонка исключены на уровне базы.
        _ = try await Functions.functions().httpsCallable(
            "submitDeviceTransferPayload"
        ).call([
            "sessionID": info.sessionID,
            "trustedPublicKey": ownKey.publicKey.rawRepresentation
                .base64EncodedString(),
            "encryptedPayload": combined.base64EncodedString()
        ])
    }

    /// Удаляет временный документ сессии (отмена с любой стороны).
    func deleteSession(sessionID: String) async {
        try? await sessionDocument(sessionID).delete()
    }

    // MARK: - Crypto

    /// Shared secret → симметричный ключ AES-GCM через HKDF-SHA256.
    /// Соль — session id: известен обоим устройствам, но не
    /// передаётся в открытом виде вместе с ключом.
    private static func symmetricKey(
        sharedSecret: SharedSecret,
        sessionID: String
    ) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(sessionID.utf8),
            sharedInfo: hkdfSharedInfo,
            outputByteCount: 32
        )
    }

    private static func encryptPayload(
        json: Data,
        ownPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        deviceBPublicKey: Curve25519.KeyAgreement.PublicKey,
        sessionID: String
    ) throws -> AES.GCM.SealedBox {
        let sharedSecret = try ownPrivateKey.sharedSecretFromKeyAgreement(
            with: deviceBPublicKey
        )
        let key = symmetricKey(sharedSecret: sharedSecret, sessionID: sessionID)
        return try AES.GCM.seal(json, using: key)
    }

    private static func decryptPayload(
        encryptedPayload: String,
        trustedPublicKeyBase64: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        sessionID: String
    ) throws -> CloudTokenPayload {
        guard let trustedPublicKeyData = Data(base64Encoded: trustedPublicKeyBase64),
              let trustedPublicKey = try? Curve25519.KeyAgreement.PublicKey(
                  rawRepresentation: trustedPublicKeyData
              ),
              let combined = Data(base64Encoded: encryptedPayload) else {
            throw DeviceTransferError.invalidSessionData
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(
            with: trustedPublicKey
        )
        let key = symmetricKey(sharedSecret: sharedSecret, sessionID: sessionID)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let json = try AES.GCM.open(sealedBox, using: key)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudTokenPayload.self, from: json)
    }

    /// Гонка операции с таймаутом: если Firestore не подтверждает
    /// запись/чтение за `backendTimeout` секунд (например, база
    /// `(default)` не создана в консоли или правила не задеплоены),
    /// бросаем `backendUnavailable` вместо бесконечного ожидания.
    ///
    /// Unstructured-задачи, а не `withThrowingTaskGroup`: группа при
    /// выходе ждала бы завершения всех child-задач, и зависший
    /// сетевой вызов Firestore не отпускал бы функцию даже после
    /// срабатывания таймаута. Continuation резюмится ровно один раз —
    /// победившая задача «выигрывает», проигравшая завершается молча.
    private func withBackendTimeout<T>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BackendTimeoutResumeGate()

            let work = Task {
                do {
                    let value = try await operation()
                    if gate.claim() {
                        continuation.resume(returning: value)
                    }
                } catch {
                    if gate.claim() {
                        continuation.resume(throwing: error)
                    }
                }
            }

            Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.backendTimeout * 1_000_000_000)
                )
                work.cancel()
                if gate.claim() {
                    continuation.resume(
                        throwing: DeviceTransferError.backendUnavailable
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func sessionDocument(_ sessionID: String) -> DocumentReference {
        firestore
            .collection(collectionName)
            .document(sessionID)
    }
}

/// Пропускает только первого «претендента» на resume continuation:
/// в `withBackendTimeout` гоняются задача операции и таймер,
/// и только один из них может завершить ожидание.
private final class BackendTimeoutResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

/// Ошибки QR-переноса сессий между устройствами.
enum DeviceTransferError: LocalizedError {
    case notAuthenticated
    case noActiveSession
    case sessionNotFound
    case sessionExpired
    case notSessionOwner
    case invalidSessionData
    case decryptionFailed
    case encryptionFailed
    case sessionCancelled
    case submissionFailed
    case backendUnavailable
    case unsupportedPayloadVersion

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Войдите в аккаунт CloudVault, чтобы перенести подключения."
        case .noActiveSession:
            return "Нет активной сессии переноса."
        case .sessionNotFound:
            return "Сессия переноса не найдена. QR-код мог устареть."
        case .sessionExpired:
            return "Сессия переноса истекла. Создайте QR-код заново."
        case .notSessionOwner:
            return "Этот QR-код принадлежит другому аккаунту."
        case .invalidSessionData:
            return "Некорректные данные сессии переноса."
        case .decryptionFailed:
            return "Не удалось расшифровать полученные данные."
        case .encryptionFailed:
            return "Не удалось зашифровать данные для переноса."
        case .sessionCancelled:
            return "Перенос отменён."
        case .submissionFailed:
            return "Не удалось отправить пакет. Проверьте соединение и повторите."
        case .backendUnavailable:
            return "Firestore не отвечает. Проверьте, что база данных создана в консоли Firebase и правила безопасности задеплоены."
        case .unsupportedPayloadVersion:
            return "Формат данных переноса не поддерживается этой версией приложения."
        }
    }
}
