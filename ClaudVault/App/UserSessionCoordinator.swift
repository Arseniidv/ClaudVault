import Foundation
import SwiftData

/// Координирует смену пользователя CloudVault: экспортирует
/// сессии уходящего пользователя, переключает `CurrentUserContext`,
/// очищает in-memory состояния облачных SDK и отменяет активные
/// передачи, чтобы данные одного аккаунта не были видны другому.
///
/// Вызывается из `AuthViewModel.observeAuthState` на каждое
/// изменение `AuthUser` — включая sign-out (`newOwnerID == nil`).
@MainActor
final class UserSessionCoordinator {

    /// Флаг разовой очистки данных, сохранённых до введения
    /// owner-изоляции: они не имеют владельца и не могут быть
    /// безопасно привязаны ни к одному аккаунту.
    static let legacyCleanupFlagKey = "ownerScopingCleanupV1"

    private let googleOAuthManager: GoogleOAuthManager
    private let dropboxAuthManager: DropboxAuthManager
    private let transferEngine: TransferEngine
    private let keychainStorage = KeychainStorageService.makeDefault()

    init(
        googleOAuthManager: GoogleOAuthManager,
        dropboxAuthManager: DropboxAuthManager,
        transferEngine: TransferEngine
    ) {
        self.googleOAuthManager = googleOAuthManager
        self.dropboxAuthManager = dropboxAuthManager
        self.transferEngine = transferEngine
    }

    /// Обрабатывает переход `oldOwnerID → newOwnerID`.
    /// `nil → user` — вход/восстановление сессии;
    /// `user → nil` — выход; `userA → userB` — смена аккаунта.
    func handleUserChange(
        from oldOwnerID: String?,
        to newOwnerID: String?
    ) async {
        // 1. Экспорт сессий уходящего пользователя ДО сброса
        //    GIDSignIn: SDK — синглтон и держит только одну
        //    Google-сессию. OneDrive/Dropbox-токены уже лежат
        //    в scoped Keychain-записях и экспорт не требуют.
        if let oldOwnerID {
            googleOAuthManager.exportSessionForOwner(oldOwnerID)
        }

        // 2. Переключаем контекст владельца — все репозитории
        //    и хранилища начнут читать данные нового пользователя.
        CurrentUserContext.shared.set(newOwnerID)

        // Отложенный email sign-in link предыдущего сценария
        // не должен пережить смену аккаунта.
        UserDefaults.standard.removeObject(
            forKey: FirebaseAuthRepository.pendingEmailLinkKey
        )

        // 3. In-memory сессии SDK previous пользователя сбрасываем:
        //    scoped-записи в Keychain сохраняются.
        googleOAuthManager.disconnectInMemory()
        dropboxAuthManager.clearInMemoryClients()

        // 4. Активная передача принадлажаем ушедшему пользователю —
        //    останавливаем на границе чанка.
        await transferEngine.cancelActive()

        // 5. При входе — разовая очистка «бесхозных» данных
        //    доисторической версии и восстановление Dropbox-клиента
        //    текущего пользователя (на старте SDK мог не поднять
        //    его, т.к. Firebase-сессия ещё не восстановилась).
        if newOwnerID != nil {
            await cleanupLegacyDataIfNeeded()
            dropboxAuthManager.restoreOwnedClient()
        }
    }

    /// Удаляет учётные данные и зеркальные сессии, сохранённые
    /// до введения owner-изоляции: у них нет владельца, поэтому
    /// они недоступны никому и представляют риск утечки.
    /// SwiftData-записи без ownerID не трогаем — они просто
    /// становятся невидимыми для всех запросов.
    private func cleanupLegacyDataIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.legacyCleanupFlagKey) else {
            return
        }
        defaults.set(true, forKey: Self.legacyCleanupFlagKey)

        _ = await keychainStorage.deleteLegacySessions()
        GoogleSessionStore.deleteLegacyItem()
        OneDriveTokenStore.deleteLegacyItems()
        DropboxSecureStorageAccess.deleteOrphanedTokens()
    }
}
