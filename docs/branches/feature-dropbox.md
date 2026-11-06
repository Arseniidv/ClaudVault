# feature/dropbox

Интеграция Dropbox: авторизация и файловые операции через SwiftyDropbox.

**Статус:** влита в `develop` (merge `3825fde`)
**Коммит:** `8e83d4c feat(dropbox): dropbox auth, service, storage adapter`

## Что реализовано

- `Infrastructure/Dropbox/` — auth-менеджер, `DropboxService` (list/search/download/upload), `DropboxStorageAdapter` для SwiftyDropbox SDK
- Подключение к единому `CloudStorageRepository`-контракту

Позднее (в `feature/security`) хранилище токенов Dropbox переведено на общий `KeychainStorageService` (`DropboxSecureStorageAccess`, `DropboxAuthManager`).

~4 файла, +703 строки.
