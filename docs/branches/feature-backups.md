# feature/backups

Пайплайн бэкапов: SwiftData-персистентность, сессии загрузки, chunked transfer, версии файлов.

**Статус:** влита в `develop` (merge `66f1a62`)
**Коммит:** `f02d8d9 feat(backups): backup pipeline — swiftdata persistence, upload sessions, chunked transfer, versions UI`

## Что реализовано

- `Data/Persistence/` — SwiftData-модели `BackupRecord`, `UploadSession`
- `Data/Mappers/` — мапперы persistence ↔ domain
- `Domain/UseCases/` — `CreateBackupRecordUseCase`, backup lifecycle
- `Infrastructure/Transfer/` — `HTTPChunkReader` для возобновляемых chunked-загрузок
- `ClaudVault/Synchronization/Models/` — модели sync-задач
- `Presentation/Backups/`, `Presentation/Versions/` — UI бэкапов и версий
- Unit-тесты: `BackupLifecycleUseCaseTests`, `CreateBackupRecordUseCaseTests`

~35 файлов, +3629 строк — самый крупный feature-коммит на момент вливания.
