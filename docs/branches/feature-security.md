# feature/security

Безопасность и интеграция с системой: Keychain-хранилище токенов, виджет, Live Activities, передача данных между устройствами.

**Статус:** активна, содержит коммит `fc89268` (на `develop` тот же код под `d4b64e8`)
**Коммит:** `fc89268 feat: Keychain token storage, widget extension, device transfer and live activities`

## Что реализовано

### Keychain-хранилище токенов
- `Infrastructure/Security/KeychainStorageService.swift`
  - `KeychainItemStore` — синхронное KV-хранилище на `SecItem` с `NSLock`; сервис `com.claudvault.storage.auth`, доступность `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, Data Protection Keychain на macOS
  - `KeychainStorageService` (actor) — `CloudAccountSession`-записи `<provider>|<email>`: save/load/delete/list
- `Domain/Entities/CloudAccountSession.swift` + `CloudProviderType`
- Миграция легаси-токенов: `DropboxSecureStorageAccess`, `OneDriveTokenStore`, `GoogleSessionStore`; провайдеры (`GoogleOAuthManager`, `DropboxAuthManager`, `OneDriveAuthManager`) переведены на общий сервис
- `Infrastructure/Security/PasswordResetService.swift`

### Виджет и Live Activities
- `CloudVaultWidget/` — `CloudVaultWidgetExtension`: статические виджеты + `CloudSyncLiveActivity`
- `Shared/` — `WidgetModels`, `CloudSyncAttributes` (общие для app и extension)
- `App/WidgetDataPublisher.swift`, `App/LiveActivityManager.swift`

### Device Transfer
- `Infrastructure/Security/DeviceTransfer/` — `QRVerificationService`, `CloudTokenStore`, `CloudTokenPayload`, `GoogleSessionStore`
- `Presentation/DeviceTransfer/` — `DeviceTransferView`, `DeviceTransferViewModel`, `QRCodeScannerView`
- `App/DeviceTransferCoordinator.swift`, `ClaudVaultIOS.entitlements`

### Прочее
- Deep links: `BackupCreationDeepLink`, `StorageDeepLink`, `BackupActionRouter`
- `CreateBackupView`, `DocumentScannerView`, обновления UI по всему `Presentation/`
- `ClaudVault.entitlements` — app groups / associated domains для виджета и transfer

~80 файлов, +5312 строк.
