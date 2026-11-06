# feature/app-shell

Каркас приложения: точка входа, DI-контейнер, координатор и навигация.

**Статус:** влита в `develop` (merge `9528765`)
**Коммит:** `1e65086 feat(app): app entry, DI container, coordinator, navigation`

## Что реализовано

- `ClaudVault/App/` — `ClaudVaultApp` (App-протокол), `AppDependencies` (DI-контейнер), координатор, `App/Navigation/`
- Тестовые заготовки: `ClaudVaultTests`, `ClaudVaultUITests`

Позднее в `develop` `App/` расширен роутерами и менеджерами (`fc89268`): `BackupActionRouter`, `BackupCreationDeepLink`, `StorageDeepLink`, `DeviceTransferCoordinator`, `LiveActivityManager`, `WidgetDataPublisher`.

~8 файлов, +341 строка.
