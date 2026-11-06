# Ветки проекта ClaudVault

Документация по содержимому каждой ветки репозитория. Ветки `feature/*` уже влиты в `develop` (Git Flow, см. корневой [README](../../README.md)).

## Основные ветки

| Ветка | Назначение | Статус |
|---|---|---|
| [main](main.md) | Стабильная версия, релизы | Активна |
| [develop](develop.md) | Интеграционная ветка, вся новая работа | Активна |

## Feature-ветки (влиты в develop)

| Ветка | Содержимое | Коммит |
|---|---|---|
| [feature/core-domain](feature-core-domain.md) | Доменные сущности, протоколы репозиториев, сервисы | `5cc9ee4` |
| [feature/auth](feature-auth.md) | Firebase Auth, биометрия, OTP, экраны входа | `de2bf9a` |
| [feature/cloud-storage](feature-cloud-storage.md) | Ядро облачных хранилищ: manager, кэш, превью | `fe7b789` |
| [feature/google-drive](feature-google-drive.md) | Google Drive API, OAuth, репозиторий | `8f4cf49` |
| [feature/dropbox](feature-dropbox.md) | Dropbox API, auth, storage adapter | `8e83d4c` |
| [feature/onedrive](feature-onedrive.md) | Microsoft Graph, OAuth PKCE, token store | `4f3ac67` |
| [feature/backups](feature-backups.md) | Пайплайн бэкапов: SwiftData, версии, chunked transfer | `f02d8d9` |
| [feature/files-ui](feature-files-ui.md) | Dashboard, браузер файлов, настройки, профиль | `d167e8f` |
| [feature/firebase-backend](feature-firebase-backend.md) | Firebase Cloud Functions + firebase.json | `989af98` |
| [feature/app-shell](feature-app-shell.md) | Точка входа, DI-контейнер, координатор, навигация | `1e65086` |
| [feature/security](feature-security.md) | Keychain-хранилище токенов, виджет, device transfer, Live Activities | `fc89268` |

## Служебные ветки

| Ветка | Содержимое | Статус |
|---|---|---|
| [chore/add-item-file](chore-add-item-file.md) | Трекинг `Item.swift` | Влита |
| [docs/readme](docs-readme.md) | Первый README с архитектурой и Git Flow | Влита |
