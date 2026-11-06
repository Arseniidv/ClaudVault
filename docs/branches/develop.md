# develop

Интеграционная ветка. Вся новая работа сходится сюда через merge feature-веток; именно отсюда делаются релизные merge в `main`.

## Содержимое

Актуальное состояние `develop` = `main` + вся новая функциональность:

- Все модули из feature-веток (см. [индекс](README.md))
- `feature/security` (`fc89268` / cherry-pick `d4b64e8`):
  - `KeychainStorageService` + `KeychainItemStore` — потокобезопасное хранение токенов облачных аккаунтов в Keychain (Data Protection Keychain на macOS, `AfterFirstUnlockThisDeviceOnly`)
  - `CloudAccountSession` — нормализованные записи `<provider>|<email>` для Google Drive, Dropbox, OneDrive с миграцией легаси-токенов
  - `CloudVaultWidgetExtension` + `Shared/` — виджет статусов синхронизации и Live Activity (`CloudSyncLiveActivity`)
  - DeviceTransfer — передача сессий между устройствами по QR (`QRVerificationService`, `CloudTokenStore`, `GoogleSessionStore`, `DeviceTransferCoordinator`)
  - Deep links: `BackupCreationDeepLink`, `StorageDeepLink`, `BackupActionRouter`
  - `PasswordResetService`, `DocumentScannerView`, `CreateBackupView`
- Firebase Functions (`bf67bff`): email-OTP/2FA, сброс пароля через SMTP, `submitDeviceTransferPayload`, `firestore.rules`, `.firebaserc`
- Документация: обновлённый README (`2308cbe`)

## Проверено

- `xcodebuild -scheme ClaudVault -destination 'platform=macOS' build` — **BUILD SUCCEEDED** (DerivedData на APFS-диске)
