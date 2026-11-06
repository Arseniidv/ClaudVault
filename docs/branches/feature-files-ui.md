# feature/files-ui

Пользовательский интерфейс: dashboard, браузер файлов, настройки, профиль, таб-навигация.

**Статус:** влита в `develop` (merge `98fd5e5`)
**Коммит:** `d167e8f feat(ui): dashboard, files browser, settings, profile, tab navigation`

## Что реализовано

- `Presentation/Dashboard/` — главный экран со сводкой
- `Presentation/Home/` — `RootView`, таб-бар
- `Presentation/Files/` / `Components/FilesView` — браузер файлов
- `Presentation/Storages/` — `StoragesView`, `StoragesViewModel` (~940 строк)
- `Presentation/Settings/`, `Presentation/Profile/`
- `Presentation/Synchronization/` — `SynchronizationView`
- `Presentation/Components/` — `QuickLookPreview`, `AudioPlayerView`, `CloudThumbnailView`, `StorageOverviewView`, `OTPCodeField`, `ActiveTransfersSectionView` и др.
- ViewModels для всех экранов

~32 файла, +4347 строк.
