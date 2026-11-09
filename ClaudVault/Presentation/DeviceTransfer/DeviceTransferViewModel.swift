import Foundation
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ClaudVaultDomain

/// ViewModel экрана переноса подключений (QR Guard).
@MainActor
@Observable
final class DeviceTransferViewModel {

    enum Mode {
        /// Новое устройство: показывает QR, ждёт зашифрованный пакет.
        case generator
        /// Доверенное устройство: сканирует QR, отправляет токены.
        case scanner
    }

    enum Phase: Equatable {
        case idle
        case working
        case awaitingScan
        /// Пакет расшифрован — ждём подтверждения пользователя
        /// перед записью токенов в Keychain.
        case awaitingRestore
        case completed
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

    init(
        qrService: QRVerificationService,
        tokenStore: CloudTokenStore,
        biometricAuth: BiometricAuthService,
        coordinator: DeviceTransferCoordinator
    ) {
        self.qrService = qrService
        self.tokenStore = tokenStore
        self.biometricAuth = biometricAuth
        self.coordinator = coordinator
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
        Task { await startGenerator() }
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

    private func startGenerator() async {
        phase = .working
        statusMessage = "Создаём защищённую сессию…"
        do {
            let url = try await qrService.beginGeneratorSession()
            qrImage = Self.qrImage(for: url.absoluteString)
            phase = .awaitingScan
            statusMessage = "Откройте приложение на старом устройстве и отсканируйте этот код для синхронизации. Код действует 10 минут."

            // Ждём зашифрованный пакет в фоне.
            Task { [weak self] in
                guard let self else { return }
                await self.receivePayload()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func receivePayload() async {
        do {
            let payload = try await qrService.awaitTransferredPayload()
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
            // Отмена — не ошибка, состояние уже idle.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Пользователь подтвердил применение полученных токенов.
    func confirmRestore() {
        guard let payload = receivedPayload else { return }
        do {
            let restored = try tokenStore.restore(payload)
            restoredProviders = restored
            receivedPayload = nil
            incomingProviders = []
            phase = .completed
            statusMessage = restored.isEmpty
                ? "Пакет применён, но подходящих подключений в нём не было."
                : "Подключения восстановлены: \(restored.joined(separator: ", "))."
        } catch {
            phase = .failed(error.localizedDescription)
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
            phase = .failed(error.localizedDescription)
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
            let payload = tokenStore.collect()
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
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - QR rendering

    /// Рендерит строку в CGImage через CIQRCodeGenerator.
    static func qrImage(for string: String, scale: CGFloat = 8) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    func reset() {
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
