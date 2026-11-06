# feature/auth

Аутентификация пользователей: Firebase Auth, биометрия, OTP и экраны входа/регистрации/сброса пароля.

**Статус:** влита в `develop` (merge `3920ad3`)
**Коммит:** `de2bf9a feat(auth): firebase auth, biometrics, OTP, login/register/reset flows`

## Что реализовано

- `Domain/Authentication/` — auth-сущности и протоколы, `AuthError`
- `Domain/UseCases/` — use cases аутентификации
- `Data/Repositories/FirebaseAuthRepository.swift` — реализация поверх Firebase Auth
- `Infrastructure/Security/` — `BiometricAuthService` (Face ID / Touch ID), `OTPService`
- `Presentation/Authentication/Views/` — `LoginView`, `RegisterView`, `ResetPasswordView`
- `Presentation/Security/AppLockView.swift` — локальная блокировка приложения
- `Presentation/ViewModels/AuthViewModel.swift` — состояние auth-флоу
- UI-компоненты: `OTPCodeField`

~18 файлов, +1609 строк.
