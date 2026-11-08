# ClaudVault

ClaudVault — кроссплатформенное приложение для работы с облачными хранилищами: объединённый браузер файлов, бэкапы с историей версий, передача файлов между провайдерами и расширенная интеграция с macOS/iPadOS. SwiftUI + SwiftData, чистая архитектура (Domain / Data / Infrastructure / Presentation).

## Возможности

- **Облачные хранилища**: Google Drive, Dropbox, OneDrive — несколько аккаунтов, обзор занятого места, browsинг папок, глобальный поиск по всем подключённым облакам, загрузка файлов и папок, создание папок, переименование/удаление, превью (QuickLook, PDF, аудио, видео, документы/ODT), история недавних открытых файлов.
- **Бэкапы**: создание бэкапа файла или скана, версии, переименование (облачные объекты переименовываются через API провайдера), возобновление прерванных загрузок (chunked transfer через `TransferEngine`/`HTTPChunkReader`), перенос бэкапов между провайдерами.
- **Аутентификация**: Firebase Auth (email/password, passwordless по ссылке), биометрия (Face ID / Touch ID), OTP 2FA, сброс пароля через email.
- **Синхронизация**: фоновые задачи передачи файлов между хранилищами, возобновление незавершённых сессий из журнала после восстановления подключений (`TransferEngine.resumePending`).
- **Безопасное хранение токенов**: `KeychainStorageService` поверх `SecItem` — Data Protection Keychain на macOS, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, потокобезопасный `KeychainItemStore` (NSLock), owner-scoped ключи `<ownerID>|<provider>|<email>`. Токены Google Drive, Dropbox и OneDrive хранятся в Keychain с автоматической миграцией легаси-данных.
- **Виджет и Live Activities**: `CloudVaultWidgetExtension` — статусы синхронизации на рабочем столе/экране «Домой», Live Activity для активных передач (`CloudSyncLiveActivity`) и аудио (`AudioLiveActivity`), интерактивный аудио-виджет (`AudioPlayerWidget`) и аудио-плеер с App Intents (`AudioPlayerIntents`, `AudioCommandBus`, `AudioActivityAttributes`).
- **Передача между устройствами**: DeviceTransfer — экспорт сессий облачных аккаунтов по QR-коду с верификацией (`QRVerificationService`, `CloudTokenStore`, `GoogleSessionStore`).
- **Firebase Functions**: email-OTP/2FA, сброс пароля через SMTP, приём payload'ов device transfer (`functions/`, Node.js 20).
- **Интеграция с macOS**: Finder Sync extension (`ClaudVaultFinderSync.appex`), пункт «Open in Cloud Manager» в контекстном меню Finder и Services, Menu Bar приложение, Radial Menu с глобальной горячей клавишей, Accessibility permissions, мост к Finder (`FinderExtensionBridge`), deep links (`claudvault://`).
- **iPad/Mac layouts**: специализированные корневые экраны (`IPadRootView`, `IPadFilesView`, `MacRootView`, `MacBackupTable`).
- **File Actions**: реестр действий для облачных файлов (`FileActionRegistry`, handlers) — открыть, скачать, поделиться, бэкап и т.д.

## Структура проекта

```
ClaudVault.xcodeproj/       # Xcode-проект (targets: ClaudVault, ClaudVaultTests,
                            # ClaudVaultUITests, CloudVaultWidgetExtension,
                            # ClaudVaultFinderSync)
ClaudVault/                 # Основное приложение
├── App/                    # Точка входа, DI-контейнер, координаторы,
│                           # MacAppDelegate, MenuBar, RadialMenuAppIntegration,
│                           # LiveActivityManager, AudioLiveActivityManager,
│                           # Navigation, UserSessionCoordinator, BackupActionRouter,
│                           # DeviceTransferCoordinator, WidgetDataPublisher
├── Domain/                 # Entities, repository protocols, use cases, сервисы
│   ├── Authentication/     # Auth-сущности и протоколы
│   ├── Entities/           # CloudFile, BackupRecord, UploadSession, AudioTrack и др.
│   ├── Repositories/       # Протоколы CloudStorageRepository, AuthRepository...
│   ├── Services/           # FileHashing, MailComposer, SafeFileName, UploadFileNaming
│   └── UseCases/           # Use cases по фичам (auth, storage, backups, transfer, rename)
├── Data/                   # Реализации репозиториев, SwiftData, мапперы
├── Infrastructure/         # Провайдеры и системные сервисы
│   ├── GoogleDrive/        # Google Drive API, OAuth, репозиторий
│   ├── Dropbox/            # Dropbox API, auth, storage adapter
│   ├── OneDrive/           # Microsoft Graph, OAuth PKCE, token store
│   ├── Security/           # KeychainStorageService, biometrics, OTP,
│   │                       # DeviceTransfer (QR, CloudTokenStore, GoogleSessionStore)
│   ├── Audio/              # AudioPlayerService, AudioMetadataExtractor, AudioSourceResolver
│   ├── FileActions/        # FileActionRegistry и handlers
│   ├── FileSelection/      # FileSelection, resolvers, access
│   ├── SystemIntegration/  # FinderExtensionBridge, GlobalHotKeyManager,
│   │                       # AccessibilityPermissionManager, ProviderAvailabilityService
│   ├── Thumbnails/         # Генерация миниатюр
│   └── Transfer/           # TransferEngine, chunked transfer
├── Presentation/           # SwiftUI: Views, ViewModels, Components
│   ├── Authentication/     # Экраны входа/регистрации/сброса пароля
│   ├── Backups/            # Список бэкапов, создание, сканер, глобальный поиск, папки, переименование
│   ├── Components/         # Общие UI-компоненты, поиск, недавние файлы, мини-плеер
│   ├── DeviceTransfer/     # QR-перенос сессий
│   ├── FilePreview/        # PDF/Audio/Video/Document preview
│   ├── Home/               # RootView, dashboard
│   ├── IPad/               # iPad-специфичные экраны
│   ├── Mac/                # macOS-специфичные экраны
│   ├── RadialMenu/         # Radial Menu UI и координатор
│   ├── Security/           # AppLockView
│   ├── Settings/           # Настройки
│   ├── Storages/           # CloudFolderBrowser, StorageProvider, глобальный поиск, папки
│   ├── Synchronization/    # Sync UI
│   ├── Versions/           # BackupRecordDetailView (версии, переименование)
│   └── ViewModels/         # ViewModels по фичам
├── Synchronization/        # Модели sync-задач
├── Enum/                   # AppColors и общие enum'ы
├── ClaudVaultTests/        # Unit-тесты (use cases, TransferEngine, QRCodeGenerator, AccountIsolation)
└── ClaudVaultUITests/      # UI-тесты

CloudVaultWidget/           # Extension виджета, CloudSyncLiveActivity,
                            # AudioLiveActivity, AudioPlayerWidget
FinderSyncExtension/        # macOS Finder Sync extension (ClaudVaultFinderSync.appex)
Shared/                     # Общие модели для app, widget, audio intents,
                            # отмена загрузок, палитра провайдеров
SharedFinderSync/           # Общий код между Finder Sync и основным приложением
functions/                  # Firebase Cloud Functions (Node.js 20)
docs/                       # Документация, спецификации, описание веток
```

Целевые платформы: iOS, macOS, visionOS, iPadOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`).

## Зависимости

Swift Package Manager (резолвятся Xcode автоматически):

- **Firebase** (Auth, Firestore, Analytics)
- **GoogleSignIn**, **AppAuth**
- **SwiftyDropbox**, **Kingfisher**

Системные фреймворки: SwiftUI, SwiftData, AVFoundation, PDFKit, AppIntents, FinderSync, ServiceManagement.

Бэкенд: Firebase Functions (`functions/`, Node.js 20) — см. `firebase.json`, `firestore.rules`, `.firebaserc`. Экспортируемые функции: `requestEmailOtp`, `verifyEmailOtp` (2FA), `requestPasswordResetCode`, `confirmPasswordReset`, `submitDeviceTransferPayload`, `send2FACode` (алиас). SMTP для email-OTP и сброса пароля настраивается через `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER` (`defineString`) и secret `SMTP_PASS` (`firebase functions:secrets:set SMTP_PASS`).

## Сборка

1. Открыть `ClaudVault.xcodeproj` в Xcode.
2. Убедиться, что `GoogleService-Info.plist` на месте (Firebase config).
3. При работе с backend: `cd functions && npm install` (Node.js 20); секрет `SMTP_PASS` задаётся через `firebase functions:secrets:set SMTP_PASS`.
4. Собрать нужную схему:
   - `ClaudVault` — основное приложение (iOS / macOS / visionOS).
   - `ClaudVaultTests` — unit-тесты.
   - `ClaudVaultUITests` — UI-тесты.
   - `CloudVaultWidgetExtension` — виджет и Live Activities.
   - `ClaudVaultFinderSync` — Finder Sync extension для macOS.
5. Для macOS Finder Sync extension после установки включить расширение в **System Settings → General → Login Items & Extensions → Finder Extensions**.

> App Group `group.com.Arseniidv.ClaudVault` используется для обмена данными между app, widget и Finder Sync — убедитесь, что он добавлен в provisioning profile для всех targets.

> **Важно**: если проект лежит на exFAT/внешнем томе (например, «MY Data»), macOS создаёт AppleDouble-файлы `._*`, которые ломают сборку (pcm-модули Firebase, codesign виджета) и портят `.git`. Держите DerivedData на системном APFS-диске — в Xcode это поведение по умолчанию; при сборке из CLI **не** указывайте `-derivedDataPath` внутрь проекта на таком томе. `.gitignore` уже исключает `._*`, но если том exFAT, периодически проверяйте `.git` на наличие `._*` файлов.

## Конфигурация инструментов

- Xcode 16+ (проект использует file-system synchronized groups)
- iOS 17+ / macOS 14+ / iPadOS 17+ / visionOS 1+ (SwiftData, SwiftUI, AppIntents)
- Node.js 20 — для Firebase Functions

## Ветки

Git Flow (облегчённый). Содержимое каждой ветки описано в [docs/branches/](docs/branches/README.md):

- `main` — стабильная версия, релизы тегируются semver (`v0.1.0`)
- `develop` — интеграционная ветка, вся новая работа идёт сюда
- `feature/<name>` — новые фичи (от `develop`)
- `fix/<name>` — исправления
- `hotfix/<name>` — срочные правки в `main`

Текущие feature-ветки соответствуют модулям приложения: `feature/auth`, `feature/cloud-storage`, `feature/google-drive`, `feature/dropbox`, `feature/onedrive`, `feature/backups`, `feature/files-ui`, `feature/firebase-backend`, `feature/app-shell`, `feature/core-domain`, `feature/security`, `feature/media-transfer`.

Активная рабочая ветка на момент аудита: `fix/security-vulnerabilities`.

## Безопасность

- Токены облачных провайдеров и сессии хранятся только в Keychain.
- Изоляция аккаунтов: `CurrentUserContext` + `UserSessionCoordinator` — при смене/выходе пользователя сессии облачных SDK сбрасываются, активные передачи отменяются, legacy-данные без владельца очищаются.
- Имена файлов, приходящие из облачных провайдеров, санитизируются (`SafeFileName`) перед записью на диск; загрузка с пользовательским именем идёт через `UploadFileNaming` (hard link/копия во временной директории).
- Firebase Functions используют секреты через `defineSecret`/`defineString`, в коде нет hardcoded credentials.
- `GoogleService-Info.plist` содержит Firebase API key — это идентификатор, а не секрет; рекомендуется ограничить ключ в Google Cloud Console по bundle id `my.ClaudVault`.
- Подробный аудит безопасности: [SECURITY_AUDIT.md](SECURITY_AUDIT.md).
