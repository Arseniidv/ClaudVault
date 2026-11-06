# feature/core-domain

Доменные сущности, протоколы репозиториев и доменные сервисы — фундамент чистой архитектуры приложения.

**Статус:** влита в `develop` (merge `4e23e0a`)
**Коммит:** `5cc9ee4 feat(domain): core entities, repository protocols, domain services`

## Что реализовано

- `ClaudVault/Domain/Entities/` — доменные модели: `CloudFile`, `BackupRecord`, `UploadSession`, `Item` и др.
- `ClaudVault/Domain/Repositories/` — протоколы `CloudStorageRepository`, `AuthRepository`, `FileAccessRepository` и др.
- `ClaudVault/Domain/Services/` — `FileHashing` (протокол), `MailComposer`
- `ClaudVault/Data/FileSystem/` — файловая абстракция
- `ClaudVault/Infrastructure/SHA256FileHasher.swift` — реализация хеширования файлов

~18 файлов, +741 строка.
