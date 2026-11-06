# feature/firebase-backend

Firebase-бэкенд: Cloud Functions и конфигурация проекта.

**Статус:** влита в `develop` (merge `8ad0be4`)
**Коммит:** `989af98 feat(backend): firebase functions + firebase.json`

## Что реализовано

- `functions/index.js` — первые Cloud Functions (email-OTP, ~177 строк)
- `functions/package.json` — зависимости: `firebase-admin`, `firebase-functions`, `nodemailer`; Node.js 20
- `firebase.json` — конфигурация хостинга/functions/predeploy

Позднее в `develop` функции расширены (`bf67bff`): `requestEmailOtp`/`verifyEmailOtp` (2FA), `requestPasswordResetCode`, `confirmPasswordReset`, `submitDeviceTransferPayload`, `send2FACode`; добавлены `firestore.rules` и `.firebaserc`.
