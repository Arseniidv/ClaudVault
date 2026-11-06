# feature/cloud-storage

Ядро работы с облачными хранилищами: менеджер провайдеров, кэш файлов, миниатюры, обзор занятого места.

**Статус:** влита в `develop` (merge `80d466b`)
**Коммит:** `fe7b789 feat(storage): cloud storage core — manager, file cache, thumbnails, usage`

## Что реализовано

- `Data/Repositories/Manager/` — оркестрация нескольких облачных аккаунтов
- `Data/Persistence/Models/` — SwiftData-модели кэша облачных файлов
- `Infrastructure/Thumbnails/CloudThumbnailCache.swift` — кэш миниатюр
- `Presentation/Storages/` — `StorageProvider`, `StoragesView`, `CloudFolderBrowserView`
- `Domain/UseCases/` — сценарии работы с хранилищами
- `StorageOverviewView` — сводка занятого места по провайдерам

~7 файлов, +515 строк.
