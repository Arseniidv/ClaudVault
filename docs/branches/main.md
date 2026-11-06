# main

Стабильная ветка проекта. Содержит проверенный код, пригодный для релизов; релизы тегируются semver (`v0.1.0`).

## Содержимое

Ветка получала изменения через merge-коммиты из `develop` (например, `4de9b61 merge: develop into main`).

По состоянию на последний merge в `main` входит:

- Весь доменный слой и use cases (`feature/core-domain`)
- Аутентификация: Firebase Auth, биометрия, OTP (`feature/auth`)
- Ядро облачных хранилищ и три провайдера: Google Drive, Dropbox, OneDrive
- Пайплайн бэкапов с версиями и SwiftData-персистентностью (`feature/backups`)
- UI: dashboard, браузер файлов, настройки, профиль (`feature/files-ui`)
- Firebase Cloud Functions бэкенд (`feature/firebase-backend`)
- Каркас приложения: DI, координатор, навигация (`feature/app-shell`)
- Документация: README с архитектурой и описанием веток (`docs/readme`)

## Правила работы

- Прямые коммиты в `main` не делаются — только merge из `develop` или `hotfix/*`
- Новая работа всегда начинается от `develop`
