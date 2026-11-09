import Foundation
import OSLog
import CoreGraphics
import ClaudVaultDomain

/// ViewModel экрана переноса подключений (QR Guard).
@MainActor
@Observable
final class DeviceTransferViewModel {

    private static let logger = Logger(
        subsystem: "ClaudVault",
        category: "device-transfer"
    )

    enum Mode {
        /// Новое устройство: показывает QR, ждёт зашифрованный пакет.
        case generator
        /// Доверенное устройство: сканирует QR, отправляет токены.
        case scanner
    }

    enum Phase: Equatable {
        case idle
        case working
        /// Сессия создана в Firestore, QR-код рендерится.
        case generatingQRCode
        case awaitingScan
        /// Пакет расшифрован — ждём подтверждения пользователя
        /// перед записью токенов в Keychain.
        case awaitingRestore
        case completed
        /// Срок действия сессии истёк — QR больше не действителен.
        case expired
        case failed(String)
    }

    // MARK: - State

    var mode: Mode?
    var phase: Phase = .idle
    var qrImage: CGImage?
    var statusMessage = ""
    var restoredProviders: [String] = []
    var manualSessionInput = ""
    var isScannerPresented = false

    /// Сессия, ожидающая явного подтверждения пользователя
    /// (deep-link или отсканированный QR).
    struct PendingTransfer {
        let sessionID: String
        let ownerEmail: String?
        let createdAt: Date?
    }
    private(set) var pendingTransfer: PendingTransfer?

    /// Расшифрованный пакет, ожидающий подтверждения на новом
    /// устройстве. Токены не покидают память до `confirmRestore()`.
    private var receivedPayload: CloudTokenPayload?
    /// Имена провайдеров из полученного пакета — для экрана подтверждения.
    private(set) var incomingProviders: [String] = []

    // MARK: - Dependencies

    private let qrService: QRVerificationService
    private let tokenStore: CloudTokenStore
    private let biometricAuth: BiometricAuthService
    private let coordinator: DeviceTransferCoordinator
    private let qrGenerator: QRCodeGenerator

    /// Задачи активного сценария генератора: создание сессии
    /// и ожидание пакета. Отменяются в `reset()`/`cancelGenerator()`.
    private var generatorTask: Task<Void, Never>?
    private var payloadTask: Task<Void, Never>?
    /// Поколение сценария генератора: результаты запоздавших
    /// асинхронных операций не должны перезаписывать состояние
    /// нового запуска или сброшенного экрана.
    private var generatorGeneration = 0

    init(
        qrService: QRVerificationService,
        tokenStore: CloudTokenStore,
        biometricAuth: BiometricAuthService,
        coordinator: DeviceTransferCoordinator,
        qrGenerator: QRCodeGenerator = QRCodeGenerator()
    ) {
        self.qrService = qrService
        self.tokenStore = tokenStore
        self.biometricAuth = biometricAuth
        self.coordinator = coordinator
        self.qrGenerator = qrGenerator
        // Если deep-link пришёл, пока экран уже открыт, обрабатываем
        // его сразу — иначе ссылка пролежит до следующего показа
        // экрана и может оказаться устаревшей.
        coordinator.onIncomingURL = { [weak self] in
            self?.consumePendingDeepLink()
        }
    }

    // MARK: - Mode selection

    func chooseGenerator() {
        mode = .generator
        // Отменяем предыдущий запуск до создания нового — иначе два
        // beginGeneratorSession могут гоняться за pendingSessionID.
        generatorTask?.cancel()
        payloadTask?.cancel()
        let task = Task { await startGenerator() }
        generatorTask = task
    }

    func chooseScanner() {
        mode = .scanner
        isScannerPresented = true
    }

    /// Вызывается при появлении экрана: если пришла deep-link
    /// `claudvault://verify?session=…`, открываем подтверждение —
    /// отправка токенов запустится только после явного действия.
    func consumePendingDeepLink() {
        guard let url = coordinator.consumePendingVerificationURL(),
              let sessionID = QRVerificationService.sessionID(
                  from: url.absoluteString
              ) else { return }
        mode = .scanner
        Task { await requestTransferApproval(sessionID: sessionID) }
    }

    // MARK: - Generator

    /// Полный конвейер генератора, разбитый на этапы:
    /// создание защищённой сессии → генерация QR-кода → ожидание пакета.
    /// Каждый этап либо переводит UI в следующее состояние,
    /// либо завершает его контролируемой ошибкой — бесконечной
    /// загрузки быть не должно.
    private func startGenerator() async {
        // Новое поколение: результаты всех предыдущих запусков
        // (в т.ч. запоздавших после отмены) игнорируются.
        generatorGeneration += 1
        let generation = generatorGeneration

        phase = .working
        statusMessage = "Создаём защищённую сессию…"
        qrImage = nil
        receivedPayload = nil
        incomingProviders = []
        restoredProviders = []

        do {
            // Этап 1: защищённая сессия в Firestore (с таймаутом
            // внутри сервиса — зависший backend не вешает UI).
            let url = try await qrService.beginGeneratorSession()
            guard isActiveGeneration(generation) else { return }

            // Этап 2: рендер QR-кода вне главного потока.
            phase = .generatingQRCode
            statusMessage = "Генерируем QR-код…"
            let image = try await qrGenerator.generate(
                from: url.absoluteString
            )
            guard isActiveGeneration(generation) else { return }

            // Этап 3: QR показан, ждём зашифрованный пакет в фоне.
            qrImage = image
            phase = .awaitingScan
            statusMessage = "Откройте приложение на старом устройстве и отсканируйте этот код для синхронизации. Код действует 10 минут."

            payloadTask = Task { [weak self] in
                guard let self else { return }
                await self.receivePayload(generation: generation)
            }
        } catch {
            // Отмена и устаревшее поколение — не ошибки: состояние
            // уже принадлежит новому запуску или сброшено вызывающим.
            guard isActiveGeneration(generation),
                  !Task.isCancelled,
                  !(error is CancellationError),
                  error as? DeviceTransferError != .sessionCancelled
            else { return }
            qrService.cancelGeneratorSession()
            qrImage = nil
            phase = .failed(failureMessage(for: error))
        }
    }

    /// Приводит ошибку к понятному пользователю сообщению.
    /// Доменные ошибки уже содержат готовый русский текст;
    /// технические NSError (Firestore, Functions, Keychain)
    /// показываем общим текстом, а детали пишем в лог — иначе
    /// экран «падает без видимой причины».
    private func failureMessage(for error: Error) -> String {
        if let transferError = error as? DeviceTransferError {
            return transferError.localizedDescription
        }
        if let qrError = error as? QRCodeGenerator.GenerationError {
            return qrError.localizedDescription
        }
        Self.logger.error(
            "Device transfer failed: \(error.localizedDescription, privacy: .public)"
        )
        return "Не удалось завершить перенос. Проверьте соединение и попробуйте ещё раз."
    }

    /// true, пока поколение `generation` остаётся актуальным
    /// и породившая его задача не отменена.
    private func isActiveGeneration(_ generation: Int) -> Bool {
        generation == generatorGeneration && !Task.isCancelled
    }

    private func receivePayload(generation: Int) async {
        do {
            let payload = try await qrService.awaitTransferredPayload()
            guard isActiveGeneration(generation) else { return }
            let providers = Self.providerNames(in: payload)
            guard !providers.isEmpty else {
                phase = .completed
                statusMessage = "Пакет получен, но подключённых облаков в нём не было."
                return
            }
            // Не применяем токены молча: показываем, что именно
            // будет записано в Keychain, и ждём подтверждения.
            receivedPayload = payload
            incomingProviders = providers
            // QR мёртв: сессия уже approved, код больше ничего не открывает.
            qrImage = nil
            phase = .awaitingRestore
            statusMessage = "Получены подключения: \(providers.joined(separator: ", ")). Применить их на этом устройстве?"
        } catch DeviceTransferError.sessionCancelled {
            // Отмена — не ошибка, состояние уже принадлежит
            // новому запуску или сброшено reset()/cancelGenerator().
        } catch DeviceTransferError.sessionExpired {
            // Сессия истекла: QR недействителен, показываем
            // отдельное состояние с возможностью создать новый код.
            guard isActiveGeneration(generation) else { return }
            qrImage = nil
            phase = .expired
            statusMessage = DeviceTransferError.sessionExpired
                .localizedDescription
        } catch {
            guard isActiveGeneration(generation) else { return }
            qrImage = nil
            phase = .failed(failureMessage(for: error))
        }
    }

    /// Пользователь подтвердил применение полученных токенов.
    func confirmRestore() {
        guard let payload = receivedPayload else { return }
        do {
            guard let ownerID = CurrentUserContext.shared.ownerID else {
                throw DeviceTransferError.notAuthenticated
            }
            let restored = try tokenStore.restore(
                payload,
                ownerID: ownerID
            )
            restoredProviders = restored
            receivedPayload = nil
            incomingProviders = []
            phase = .completed
            statusMessage = restored.isEmpty
                ? "Пакет применён, но подходящих подключений в нём не было."
                : "Подключения восстановлены: \(restored.joined(separator: ", "))."
            // Токены записаны в Keychain — просим StoragesViewModel
            // переиграть восстановление сессий, иначе импорт
            // был бы невидим до перезапуска приложения.
            coordinator.onConnectionsRestored?()
        } catch {
            phase = .failed(failureMessage(for: error))
        }
    }

    /// Пользователь отклонил полученный пакет — токены не записываются.
    func cancelRestore() {
        receivedPayload = nil
        incomingProviders = []
        mode = nil
        phase = .idle
        qrImage = nil
        statusMessage = ""
    }

    /// Имена провайдеров, представленных в пакете.
    private static func providerNames(in payload: CloudTokenPayload) -> [String] {
        var names: [String] = []
        if payload.oneDrive != nil { names.append("OneDrive") }
        if payload.dropbox != nil { names.append("Dropbox") }
        if let google = payload.google {
            // Email помогает отличить аккаунт, когда подключено
            // несколько Google-аккаунтов.
            names.append(
                google.email.isEmpty
                    ? "Google Drive"
                    : "Google Drive (\(google.email))"
            )
        }
        return names
    }

    func cancelGenerator() {
        generatorGeneration += 1
        generatorTask?.cancel()
        generatorTask = nil
        payloadTask?.cancel()
        payloadTask = nil
        qrService.cancelGeneratorSession()
        receivedPayload = nil
        incomingProviders = []
        mode = nil
        phase = .idle
        qrImage = nil
        statusMessage = ""
    }

    // MARK: - Scanner

    /// Точка входа после сканирования QR или ручного ввода ссылки.
    /// Автоматической отправки нет — сначала показываем пользователю
    /// детали сессии и ждём явного подтверждения.
    func handleScannedValue(_ value: String) {
        guard let sessionID = QRVerificationService.sessionID(from: value) else {
            phase = .failed("Не удалось распознать QR-код переноса.")
            return
        }
        Task { await requestTransferApproval(sessionID: sessionID) }
    }

    func submitManualSession() {
        let value = manualSessionInput
        manualSessionInput = ""
        handleScannedValue(value)
    }

    /// Загружает сведения о сессии и переводит UI в состояние
    /// "ожидает подтверждения".
    private func requestTransferApproval(sessionID: String) async {
        phase = .working
        statusMessage = "Проверяем сессию…"
        isScannerPresented = false

        do {
            let info = try await qrService.scannerSessionInfo(for: sessionID)
            pendingTransfer = PendingTransfer(
                sessionID: info.sessionID,
                ownerEmail: info.ownerEmail,
                createdAt: info.createdAt
            )
            phase = .idle
            statusMessage = "Подтвердите отправку подключений на новое устройство."
        } catch {
            pendingTransfer = nil
            phase = .failed(failureMessage(for: error))
        }
    }

    /// Пользователь подтвердил отправку — запускаем биометрию
    /// и передачу пакета.
    func approvePendingTransfer() {
        guard let pending = pendingTransfer else { return }
        Task { await approveAndSend(sessionID: pending.sessionID) }
    }

    func cancelPendingTransfer() {
        pendingTransfer = nil
        phase = .idle
        statusMessage = ""
    }

    /// Полный цикл доверенного устройства: биометрия → сбор токенов
    /// → шифрование → отправка через Cloud Function.
    private func approveAndSend(sessionID: String) async {
        pendingTransfer = nil
        phase = .working
        statusMessage = "Подтвердите передачу биометрией…"
        isScannerPresented = false

        do {
            let info = try await qrService.scannerSessionInfo(for: sessionID)
            _ = try await biometricAuth.authenticateForSensitiveOperation(
                reason: "Подтвердите передачу подключений облаков на новое устройство"
            )

            statusMessage = "Собираем подключения…"
            // Токены собираются только для текущего пользователя
            // CloudVault — чужие сессии в пакет не попадают.
            guard let ownerID = CurrentUserContext.shared.ownerID else {
                phase = .failed(DeviceTransferError.notAuthenticated
                    .localizedDescription)
                return
            }
            let payload = await tokenStore.collect(ownerID: ownerID)
            let hasTokens = payload.oneDrive != nil
                || payload.dropbox != nil
                || payload.google != nil
            guard hasTokens else {
                phase = .failed(
                    "На этом устройстве нет подключённых облаков — нечего передавать."
                )
                return
            }

            statusMessage = "Отправляем зашифрованный пакет…"
            try await qrService.sendPayload(payload, to: info)

            phase = .completed
            statusMessage = "Данные отправлены. На новом устройстве они появятся автоматически."
        } catch let error as BiometricAuthError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(failureMessage(for: error))
        }
    }

    func reset() {
        generatorGeneration += 1
        generatorTask?.cancel()
        generatorTask = nil
        payloadTask?.cancel()
        payloadTask = nil
        qrService.cancelGeneratorSession()
        mode = nil
        phase = .idle
        qrImage = nil
        statusMessage = ""
        restoredProviders = []
        pendingTransfer = nil
        receivedPayload = nil
        incomingProviders = []
        isScannerPresented = false
    }
}
