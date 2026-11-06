# ClaudVault

iOS-приложение для работы с облачными хранилищами: объединённый браузер файлов, бэкапы с историей версий и отслеживание загрузок. SwiftUI + SwiftData, чистая архитектура (Domain / Data / Infrastructure / Presentation).

## Возможности

- **Облачные хранилища**: Google Drive, Dropbox, OneDrive — подключение нескольких аккаунтов, обзор занятого места, browsинг папок, превью (QuickLook, аудио-плеер, миниатюры).
- **Бэкапы**: создание бэкапа файла, версии, возобновление прерванных загрузок (chunked transfer через `HTTPChunkReader`).
- **Аутентификация**: Firebase Auth (email/password), биометрия (Face ID / Touch ID), OTP.
- **Синхронизация**: фоновые задачи передачи файлов между хранилищами.

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
│                         # Security (biometrics/OTP), Thumbnails, Transfer
├── Presentation/         # SwiftUI: Views, ViewModels, Components, TabView
├── Synchronization/      # Модели sync-задач
├── Enum/                 # AppColors и общие enum'ы
├── ClaudVaultTests/      # Unit-тесты use cases
└── ClaudVaultUITests/    # UI-тесты
```

## Зависимости

Swift Package Manager (резолвятся Xcode автоматически):

- **Firebase** (Auth, Firestore, Analytics)
- **GoogleSignIn**, **AppAuth**
- **SwiftyDropbox**, **Kingfisher**

Бэкенд: Firebase Functions (`functions/`, Node.js) — см. `firebase.json`.

## Сборка

1. Открыть `ClaudVault.xcodeproj` в Xcode.
2. Убедиться, что `GoogleService-Info.plist` на месте (Firebase config).
3. Собрать схему `ClaudVault` на iOS-симуляторе или устройстве.

## Ветки

Git Flow (облегчённый):

- `main` — стабильная версия, релизы тегируются semver (`v0.1.0`)
- `develop` — интеграционная ветка, вся новая работа идёт сюда
- `feature/<name>` — новые фичи (от `develop`)
- `fix/<name>` — исправления
- `hotfix/<name>` — срочные правки в `main`

Текущие feature-ветки соответствуют модулям приложения: `feature/auth`, `feature/cloud-storage`, `feature/google-drive`, `feature/dropbox`, `feature/onedrive`, `feature/backups`, `feature/files-ui`, `feature/firebase-backend`, `feature/app-shell`, `feature/core-domain`.

## Конфигурация инструментов

- Xcode 16+ (проект использует file-system synchronized groups)
- iOS 17+ (SwiftData, SwiftUI)
- Node.js — для Firebase Functions
