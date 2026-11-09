# ClaudVault — Security Audit & Architecture Report

Date: 2026-11-08
Scope: `ClaudVault` (multiplatform SwiftUI app: iOS + macOS), `Shared`, `CloudVaultWidget`, `functions/` (Firebase Cloud Functions), `firestore.rules`.

---

## 1. Architecture Report

### 1.1 Entry points & composition

- `ClaudVault/App/ClaudVaultApp.swift` — `@main`. Configures Firebase, SwiftyDropbox (`DropboxSecureStorageAccess`), builds `ModelContainer` via `CloudVaultModelContainer` (with in-memory fallback), builds `AppDependencies`, mounts `RootView`.
- `ClaudVault/App/AppDependencies.swift` — manual DI container (`@MainActor struct`). Wires repositories, use cases, OAuth managers, `TransferEngine`, `UserSessionCoordinator`.
- `ClaudVault/App/UserSessionCoordinator.swift` — central account-isolation point: exports outgoing user's sessions, switches `CurrentUserContext.shared.ownerID`, resets in-memory SDK sessions, cancels active transfers, one-time legacy-data cleanup.
- `ClaudVault/App/RootView.swift` (+ `AppCoordinator`, `AppRoute`) — navigation; handles `claudvault://` deep links (`StorageDeepLink`, `BackupCreationDeepLink`, device-transfer verify URL).
- `ClaudVault/ContentView.swift`, `Presentation/**` — SwiftUI views + `@Observable`/ViewModel layer.

### 1.2 Layers

- **Domain** (`ClaudVault/Domain`): entities (`CloudFile`, `BackupRecord`, `CloudAccountSession`, `TransferRecord`, …), repository protocols (`CloudStorageRepository`, `FileAccessRepository`, `TransferJournal`, `UploadSessionRepository`, `AuthRepository`), services (`FileHashing`, `SafeFileName`, `UploadFileNaming`), use cases (`CreateBackupWithUploadUseCase`, `DeleteBackupUseCase`, `TransferBackupToProviderUseCase`, `RenameBackupUseCase`, …).
- **Data** (`ClaudVault/Data`): SwiftData persistence (`CloudVaultModelContainer`, models `BackupRecordModel`, `BackupVersionModel`, `CloudFileModel`, `TransferRecordModel`, `UploadSessionModel`), repository impls (`BackupMetadataRepositoryImpl`, `GoogleDriveRepositoryImpl`, `FirebaseAuthRepository`, `UploadSessionRepositoryImpl`, `TransferJournalImpl`, `CloudFileCacheRepository`), `LocalFileAccess` (FileAccessRepository impl).
- **Infrastructure** (`ClaudVault/Infrastructure`): provider SDKs — `GoogleDrive/*` (GoogleSignIn + REST), `Dropbox/*` (SwiftyDropbox), `OneDrive/*` (MSAL-style OAuth PKCE + Graph), `Transfer/*` (chunked transfer engine, journal), `Security/*` (Keychain, biometric, OTP, password reset, device transfer), `Thumbnails`, `SHA256FileHasher`.
- **Shared** (`Shared/`): widget-facing models (`WidgetModels`, `CloudSyncAttributes`, `UploadCancellation`, …).
- **Backend**: `functions/index.js` — OTP email, password reset, `submitDeviceTransferPayload` callable; `firestore.rules` — deny-by-default with a narrowly-scoped `qr_verification_sessions` match.

### 1.3 Security-relevant mechanisms (verified)

| Concern | Implementation | Assessment |
|---|---|---|
| Token storage | `KeychainItemStore`/`KeychainStorageService`: generic-password items, service `com.claudvault.storage.auth`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecUseDataProtectionKeychain=true` on macOS, NSLock-serialized | Strong. Owner-scoped keys `<ownerID>\|<provider>\|<email>` prevent cross-account token use. |
| Account isolation | `CurrentUserContext` (thread-safe ownerID), `UserSessionCoordinator`, scoped keys everywhere (OTP flags, OneDrive tokens `onedrive\|tokens\|<ownerID>`, Dropbox `dropbox-owner\|<uid>` map) | Strong. Legacy unscoped items are deleted once at login. |
| OAuth | Google: GIDSignIn, scope `drive.file` (least privilege), ownership re-verified via `currentGIDUserIsOwned()` before token use, serialized GIDSignIn flows. Dropbox: SwiftyDropbox with custom SecureStorageAccess bridged to app Keychain. OneDrive: PKCE + ASWebAuthenticationSession, tokens in Keychain. | Good. OneDrive client ID currently empty in Info.plist → provider disabled. |
| Device transfer (QR) | ECDH Curve25519 + AES.GCM + HKDF(sessionID salt); Firestore rules allow only `pending` create/read-own/delete-own; `submitDeviceTransferPayload` callable re-checks `request.auth`, ownerUid, pending status, expiry inside a transaction. | Strong design. |
| File name sanitization | `SafeFileName.sanitized` strips path separators/control chars/`..` before writing cloud names to disk. | Good. |
| File access | `LocalFileAccess.withAccess`: `startAccessingSecurityScopedResource` balanced in `defer` + `NSFileCoordinator` read coordination. | Reasonable; bookmark helpers exist on the protocol. |
| Logging | `os.Logger` with `privacy: .public` on status codes only; `print` statements all `#if DEBUG`-gated. | Acceptable. |
| Entitlements | macOS: app-sandbox, app group `group.com.Arseniidv.ClaudVault`, network.client, keychain-access-groups. iOS: app group only (iOS sandbox implicit). | Note: **no `com.apple.security.files.user-selected.read-write`** — see VULN-005. |
| Secrets in repo | `GoogleService-Info.plist` committed (API key, project `beacon-96e41`). `GIDClientID` in Info.plist. No private keys/passwords found. | See VULN-004. |

### 1.4 macOS-specific surface

- The same `ClaudVault` target builds for macOS (`SUPPORTED_PLATFORMS` includes `macosx`; `MACOSX_DEPLOYMENT_TARGET` 15.6/27.0). AppKit code exists only for OAuth presentation (`NSWindow`/`NSApplication`) and mail composer.
- No Finder Sync extension, no XPC service, no global hotkey, no `NSPanel` UI yet — Radial Menu will be new.
- App Group `group.com.Arseniidv.ClaudVault` already provisioned in entitlements — usable for IPC shared container (must be added to any new extension target).
- `claudvault://` URL scheme registered; deep links only navigate UI (no file paths/tokens in URLs — verified `BackupCreationDeepLink`, `StorageDeepLink`, `DeviceTransferCoordinator`).

### 1.5 Reusability for Radial Menu

| Existing component | Reusable for Radial Menu? |
|---|---|
| `CloudStorageRepository` + 3 provider impls | Yes — action layer calls existing use cases/repos. |
| `CreateBackupWithUploadUseCase`, `TransferBackupToProviderUseCase`, `DeleteBackupUseCase`, `RenameBackupUseCase` | Yes — upload/download/transfer/share/info actions map onto these. |
| `TransferEngine` + `TransferJournal` | Yes — resumable chunked transfers, idempotent-ish via journal. |
| `FileAccessRepository`/`LocalFileAccess` | Yes — needs extension for bookmark resolution of externally-supplied URLs. |
| `KeychainStorageService`, `CurrentUserContext` | Yes — read-only consumption; no changes needed. |
| `SafeFileName` | Yes — reuse for any local filename derivation. |
| `AppDependencies` | Partially — Radial Menu panel can live in-process in the main app; Finder Sync ext must be stateless. |
| `CloudStorageManager` (CloudKit) | **Dead code** — no references outside its own file. Do not build on it. |

---

## 2. Vulnerability Report

| ID | Severity | Location | Description | Attack scenario | Impact | Root cause | Recommended fix | Verification |
|----|----------|----------|-------------|-----------------|--------|------------|-----------------|--------------|
| VULN-001 | **Medium** | `Infrastructure/GoogleDrive/GoogleDriveService.swift` `downloadToFile` (~L223); `Infrastructure/OneDrive/OneDriveService.swift` `downloadToFile` (~L631); `Data/Repositories/Manager/CloudStorageManager.swift` `downloadFile` (~L70) | Destination file is **silently deleted** (`removeItem`) before `moveItem`, with a gap where neither old nor new file exists. No conflict check, no atomic replace. | A download to a user-chosen path (or a Radial-Menu-initiated download) overwrites an existing file without warning; a crash between remove and move loses the original. | Data loss; violates "never silently overwrite". | Legacy pattern predating SafeFileName/transfer-engine hardening. | Write to unique temp sibling, then `FileManager.replaceItemAt`/atomic move; or fail if destination exists unless caller opted in. Apply to all download paths. | Unit test: pre-existing destination → error or explicit replace; interrupted move leaves original intact. |
| VULN-002 | **Medium** | `ClaudVault.entitlements` | macOS sandbox lacks `com.apple.security.files.user-selected.read-write` (and `.downloads.read-write`). | On macOS, security-scoped access to user-selected files outside the container may fail or behave inconsistently; Radial Menu file operations and Finder-extension handoff will hit this immediately. | Feature breakage; potential false sense of access. Also today `fileImporter`/save-panel flows may silently degrade on macOS. | Entitlement never added (iOS-first project). | Add `com.apple.security.files.user-selected.read-write` to macOS entitlements; document that extension targets need matching app-group + user-selected entitlements. | Build macOS target; verify open/save panel round-trip in sandboxed debug build. |
| VULN-003 | **Low** | `Infrastructure/Dropbox/DropboxSecureStorageAccess.swift` `getDropboxAccessToken(for:)` (~L120) | Token read by Dropbox UID does not itself verify owner; relies on caller (`getAllUserIds`→`ownedUserIds`) filtering. | If any code path queries a UID directly, a token belonging to another CloudVault account could be returned. | Cross-account credential use (mitigated today). | Ownership modeled in separate `dropbox-owner|` keys, checked only at enumeration. | Add owner check inside `getDropboxAccessToken` (return nil when `owner(ofDropboxUID:) != CurrentUserContext.ownerID`). | Unit test with two owners; assert nil for foreign UID. |
| VULN-004 | **Low** | `GoogleService-Info.plist` (repo root, bundled) | Firebase API key committed. Per Google docs this is an identifier, not a secret — but only safe if HTTP-referrer/bundle-id restrictions are set in Cloud Console. | Unrestricted key could be abused for quota/billing on the Firebase project from other apps. | Quota abuse, cost. | Key shipped in client by design. | Verify/enable API key restrictions (iOS bundle ID `my.ClaudVault`, package name) in Google Cloud Console; document. Optional: move to build-phase injection later. | Console check — manual, documented in remediation doc. |
| VULN-005 | **Low** | `ClaudVault/App/ClaudVaultApp.swift`, `RootView.swift` `onOpenURL` | `claudvault://verify?session=` deep link opens device-transfer UI automatically. | Any app/website can pop the transfer screen; however sending tokens still requires explicit user confirmation + same-account check server-side. | UI spoofing / social engineering only. | Scheme is unguessable-ish but public in Info.plist. | Acceptable; optionally gate auto-open behind a confirmation dialog (already effectively present in flow). Document as accepted risk. | Manual review of DeviceTransferView flow. |
| VULN-006 | **Low** | `Infrastructure/Transfer/ChunkSources.swift`, `Presentation/ViewModels/StoragesViewModel.swift` temp dirs | Temp files (`cloud-preview-*`, `cloud-transfer-*`, chunk files) in `FileManager.default.temporaryDirectory` with UUID names; cleanup via `defer`. On macOS sandbox this is the per-app container temp — OK. | Residual temp files after crash could retain cloud data briefly. | Low — container-private, purged by OS. | Best-effort cleanup only. | Acceptable; optionally add `.completeFileProtection`-equivalent (N/A macOS) — document. | Code review. |
| VULN-007 | **Info** | `Data/Repositories/Manager/CloudStorageManager.swift` | CloudKit-based manager appears to be **dead code** (no references). Contains the VULN-001 pattern. | — | Maintenance hazard; if accidentally wired in, inherits unsafe overwrite. | Legacy pre-provider architecture. | Delete file or mark deprecated; ensure nothing references it. | `grep CloudStorageManager` → only self. |
| VULN-008 | **Info** | `functions/index.js`, `firestore.rules` | Backend verified: OTP/reset/verification collections fully denied to clients; QR session rules enforce owner+pending+expiry; callable re-validates auth/owner/status/expiry transactionally; SMTP secrets via `defineSecret`. | — | — | — | No action. | Already verified by inspection. |

### Checked and found OK

- No tokens/passwords/file contents in logs; `print` uses are `#if DEBUG`-gated and log errors only.
- No credentials in `UserDefaults` (only emails, flags, timestamps — owner-scoped where sensitive).
- No secrets in IPC-relevant URLs; deep links carry no file paths or tokens.
- OAuth tokens never exposed to UI layer; access tokens fetched fresh via managers.
- Token revocation: `invalid_grant` deletes restored Google session; sign-out paths delete scoped Keychain items.
- OTP trust window and 2FA flag are owner-scoped in UserDefaults.
- Firestore security rules are deny-by-default.

---

## 3. Security Gate Status

- **Critical:** none confirmed.
- **High:** none confirmed.
- **Medium:** VULN-001 (silent overwrite / non-atomic download), VULN-002 (missing macOS user-selected-files entitlement — blocks safe Radial Menu file access).

**Gate decision:** No Critical/High findings. Proceed to remediation of VULN-001/VULN-002 (and cheap Lows VULN-003/VULN-007) before Radial Menu implementation, since VULN-002 directly affects the feature's file-access model.
