import SwiftUI

/// Полноэкранная блокировка приложения (Face ID / Touch ID / пароль устройства).
struct AppLockView: View {
    let biometricAuthService: BiometricAuthService
    let onUnlock: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.cyan)

                VStack(spacing: 8) {
                    Text("CloudVault заблокирован")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Подтвердите личность для продолжения")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    Task { await authenticate() }
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "faceid")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Text(isAuthenticating ? "Проверка…" : "Разблокировать")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .task { await authenticate() }
    }

    private func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            _ = try await biometricAuthService.authenticateDeviceOwner(
                reason: "Разблокируйте CloudVault"
            )
            onUnlock()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
