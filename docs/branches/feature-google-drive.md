# feature/google-drive

Интеграция Google Drive: OAuth-авторизация и Drive API v3.

**Статус:** влита в `develop` (merge `dc5db39`)
**Коммит:** `8f4cf49 feat(gdrive): google drive service, oauth, repository`

## Что реализовано

- `Infrastructure/GoogleDrive/GoogleDriveService.swift` (~820 строк) — операции Drive API: листинг, скачивание, загрузка, поиск
- `Infrastructure/GoogleDrive/GoogleOAuthManager.swift` (~274 строки) — OAuth-флоу через GoogleSignIn/AppAuth
- `Data/Repositories/GoogleDriveRepositoryImpl.swift` — маппинг Drive API на доменные `CloudFile`

~3 файла, +1322 строки.
