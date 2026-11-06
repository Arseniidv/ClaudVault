import Foundation
import FirebaseAuth
import CryptoKit

final class FirebaseAuthRepository: AuthRepository, @unchecked Sendable {
    private let auth: Auth
    
    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }
    
    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            return Self.mapUser(result.user)
        } catch {
            throw mapError(error)
        }
    }
    
    func signUp(name: String, email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
            return Self.mapUser(result.user)
        } catch {
            throw mapError(error)
        }
    }
    
    func signOut() async throws {
        do {
            try auth.signOut()
        } catch {
            throw mapError(error)
        }
    }
    
    func resetPassword(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            throw mapError(error)
        }
    }
    
    func sendEmailSignInLink(email: String) async throws {
        do {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = ActionCodeSettings()
            settings.url = URL(string: "my.ClaudVault://email-link")
            settings.handleCodeInApp = true
            try await auth.sendSignInLink(
                toEmail: trimmed,
                actionCodeSettings: settings
            )
            UserDefaults.standard.set(trimmed, forKey: Self.pendingEmailLinkKey)
        } catch {
            throw mapError(error)
        }
    }

    func isEmailSignInLink(_ url: URL) -> Bool {
        auth.isSignIn(withEmailLink: url.absoluteString)
    }

    func completeEmailSignIn(email: String, link: URL) async throws -> AuthUser {
        do {
            let result = try await auth.signIn(
                withEmail: email,
                link: link.absoluteString
            )
            try await result.user.reload()
            return Self.mapUser(result.user)
        } catch {
            throw mapError(error)
        }
    }

    /// Email, для которого была отправлена последняя ссылка входа.
    static let pendingEmailLinkKey = "pendingEmailSignInLink"

    func getCurrentUser() async -> AuthUser? {
        guard let user = auth.currentUser else { return nil }
        return Self.mapUser(user)
    }
    
    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let listener = auth.addStateDidChangeListener { _, firebaseUser in
                continuation.yield(firebaseUser.map(Self.mapUser))
            }
            
            // Fixed MainActor isolation warning by wrapping in a Task
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.removeListener(listener)
                }
            }
        }
    }
    
    private func removeListener(_ listener: AuthStateDidChangeListenerHandle) {
        auth.removeStateDidChangeListener(listener)
    }
    
    private nonisolated static func mapUser(_ user: FirebaseAuth.User) -> AuthUser {
        AuthUser(
            id: Self.stableUUID(from: user.uid),
            email: user.email ?? "",
            displayName: user.displayName,
            emailVerified: user.isEmailVerified
        )
    }
    
    private nonisolated static func stableUUID(from uid: String) -> UUID {
        let digest = SHA256.hash(data: Data(uid.utf8))
        let hash = digest.prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        
        let uuidString = [
            hash.prefix(8),
            hash.dropFirst(8).prefix(4),
            hash.dropFirst(12).prefix(4),
            hash.dropFirst(16).prefix(4),
            hash.dropFirst(20).prefix(12)
        ].map(String.init)
         .joined(separator: "-")
        
        return UUID(uuidString: uuidString) ?? UUID()
    }
    
    private func mapError(_ error: Error) -> Error {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else {
            return AuthError.unknown(error.localizedDescription)
        }
        switch code {
        case .invalidCredential, .wrongPassword, .invalidEmail:
            return AuthError.invalidCredentials
        case .userNotFound:
            return AuthError.userNotFound
        case .emailAlreadyInUse:
            return AuthError.emailAlreadyInUse
        case .weakPassword:
            return AuthError.weakPassword
        case .networkError:
            return AuthError.networkUnavailable
        case .tooManyRequests:
            return AuthError.tooManyRequests
        case .operationNotAllowed:
            return AuthError.operationNotAllowed
        case .userDisabled:
            return AuthError.sessionExpired
        default:
            return AuthError.unknown(error.localizedDescription)
        }
    }
}
