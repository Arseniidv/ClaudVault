# feature/onedrive

Интеграция OneDrive: Microsoft Graph API, OAuth с PKCE, хранение токенов.

**Статус:** влита в `develop` (merge `eaaf0ed`)
**Коммит:** `4f3ac67 feat(onedrive): microsoft graph service, oauth pkce, token store`

## Что реализовано

- `Infrastructure/OneDrive/OneDriveService.swift` (~763 строки) — операции Microsoft Graph: drive items, папки, скачивание/загрузка
- `Infrastructure/OneDrive/OneDriveAuthManager.swift` — OAuth-флоу с PKCE
- `Infrastructure/OneDrive/OneDriveTokenStore.swift` — первоначальное хранилище токенов (позже переведено на `KeychainItemStore` в `feature/security`)

~4 файла, +1345 строк.
