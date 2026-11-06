# ClaudVault

ClaudVault — iOS/macOS-приложение для работы с облачными хранилищами: объединённый браузер файлов, бэкапы с историей версий и отслеживание загрузок. SwiftUI + SwiftData, чистая архитектура (Domain / Data / Infrastructure / Presentation).

## Возможности

- **Облачные хранилища**: Google Drive, Dropbox, OneDrive — подключение нескольких аккаунтов, обзор занятого места, browsинг папок, превью (QuickLook, аудио-плеер, миниатюры).
- **Бэкапы**: создание бэкапа файла, версии, возобновление прерванных загрузок (chunked transfer через `HTTPChunkReader`).
- **Аутентификация**: Firebase Auth (email/password), биометрия (Face ID / Touch ID), OTP.
- **Синхронизация**: фоновые задачи передачи файлов между хранилищами.
- **Безопасное хранение токенов**: `KeychainStorageService` поверх `SecItem` — Data Protection Keychain на macOS, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, потокобезопасный `KeychainItemStore` (NSLock). Токены Google Drive, Dropbox и OneDrive хранятся в Keychain с автоматической миграцией легаси-данных.
- **Виджет и Live Activities**: `CloudVaultWidgetExtension` — статусы синхронизации на рабочем столе/экране «Домой», Live Activity для активных передач (`CloudSyncLiveActivity`).
- **Передача между устройствами**: DeviceTransfer — экспорт сессий облачных аккаунтов по QR-коду с верификацией (`QRVerificationService`, `CloudTokenStore`, `GoogleSessionStore`).
- **Firebase Functions**: email-OTP/2FA, сброс пароля через SMTP, приём payload'ов device transfer (`functions/`, Node.js 20).

## Структура проекта

```
ClaudVault/
├── App/                  # Точка входа, DI-контейнер, координатор, роутинг
├── Domain/               # Entities, repository protocols, use cases, сервисы
│   ├── Authentication/   # Auth-сущности и протоколы
│   ├── Entities/         # CloudFile, BackupRecord, UploadSession и др.
│   ├── Repositories/     # Протоколы CloudStorageRepository, AuthRepository...
│   ├── Services/         # FileHashing, MailComposer
│   └── UseCases/         # Use cases по фичам (auth, storage, backups)
├── Data/                 # Реализации репозиториев, SwiftData, мапперы
├── Infrastructure/       # Провайдеры: GoogleDrive, Dropbox, OneDrive,
│                         # Security (KeychainStorageService, biometrics,
│                         # OTP, DeviceTransfer), Thumbnails, Transfer
├── Presentation/         # SwiftUI: Views, ViewModels, Components, TabView
├── Synchronization/      # Модели sync-задач
├── Enum/                 # AppColors и общие enum'ы
├── ClaudVaultTests/      # Unit-тесты use cases
├── ClaudVaultUITests/    # UI-тесты
├── CloudVaultWidget/     # Extension виджета и Live Activity
├── Shared/               # Общие модели для app и widget (WidgetModels,
│                         # CloudSyncAttributes)
└── functions/            # Firebase Cloud Functions (Node.js)
```

Целевые платформы: iOS, macOS, visionOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`).

## Зависимости

Swift Package Manager (резолвятся Xcode автоматически):

- **Firebase** (Auth, Firestore, Analytics)
- **GoogleSignIn**, **AppAuth**
- **SwiftyDropbox**, **Kingfisher**

Бэкенд: Firebase Functions (`functions/`, Node.js 20) — см. `firebase.json`, `firestore.rules`, `.firebaserc`. Экспортируемые функции: `requestEmailOtp`, `verifyEmailOtp` (2FA), `requestPasswordResetCode`, `confirmPasswordReset`, `submitDeviceTransferPayload`. Для email-OTP требуется secret `SMTP_PASS` (`firebase functions:secrets:set SMTP_PASS`).

## Сборка

1. Открыть `ClaudVault.xcodeproj` в Xcode.
2. Убедиться, что `GoogleService-Info.plist` на месте (Firebase config).
3. Собрать схему `ClaudVault` на iOS-симуляторе или устройстве.

> **Важно**: если проект лежит на exFAT/внешнем томе (например, «MY Data»), macOS создаёт AppleDouble-файлы `._*`, которые ломают сборку (pcm-модули Firebase, codesign виджета). Держите DerivedData на системном APFS-диске — в Xcode это поведение по умолчанию; при сборке из CLI **не** указывайте `-derivedDataPath` внутрь проекта на таком томе.

## Ветки

Git Flow (облегчённый). Содержимое каждой ветки описано в [docs/branches/](docs/branches/README.md):

- `main` — стабильная версия, релизы тегируются semver (`v0.1.0`)
- `develop` — интеграционная ветка, вся новая работа идёт сюда
- `feature/<name>` — новые фичи (от `develop`)
- `fix/<name>` — исправления
- `hotfix/<name>` — срочные правки в `main`

Текущие feature-ветки соответствуют модулям приложения: `feature/auth`, `feature/cloud-storage`, `feature/google-drive`, `feature/dropbox`, `feature/onedrive`, `feature/backups`, `feature/files-ui`, `feature/firebase-backend`, `feature/app-shell`, `feature/core-domain`, `feature/security` (Keychain-хранилище токенов, device transfer).

## Конфигурация инструментов

- Xcode 16+ (проект использует file-system synchronized groups)
- iOS 17+ / macOS 14+ (SwiftData, SwiftUI)
- Node.js 20 — для Firebase Functions
