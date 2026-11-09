import SwiftUI

struct LoginView: View {
    let authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showResetPassword = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    VStack(spacing: 16) {
                        AuthTextField(
                            title: "Email",
                            placeholder: "example@mail.com",
                            systemImage: "envelope",
                            text: $email
                        )
                        AuthPasswordField(
                            title: "Пароль",
                            placeholder: "Введите пароль",
                            password: $password
                        )
                    }
                    if let error = authViewModel.errorMessage {
                        messageRow(text: error, color: .red)
                    }
                    if let success = authViewModel.successMessage {
                        messageRow(text: success, color: .green)
                    }
                    signInButton
                    googleSignInDivider
                    googleSignInButton

                    forgotPasswordButton

                    registerButton
                }
                .padding(24)
            }
            .background(
                AppColors.background
                    .ignoresSafeArea()
            )
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(authViewModel: authViewModel)
            }
            .navigationDestination(isPresented: $showResetPassword) {
                ResetPasswordView(authViewModel: authViewModel)
            }
            .onAppear {
                authViewModel.clearMessages()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.blue.opacity(0.9))
                .padding(.top, 48)

            Text("CLOUDVAULT")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundStyle(Color.blue.opacity(0.9))

            Text("Вход в аккаунт")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Войдите, чтобы синхронизировать резервные копии")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }
    private var signInButton: some View {
        Button {
            Task {
                await authViewModel.signIn(
                    email: email,
                    password: password
                )
            }
        } label: {
            HStack(spacing: 10) {
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(AppColors.onAccent)
                } else {
                    Text("Войти")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(AppColors.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }
    private var googleSignInDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)

            Text("или")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.4))

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)
        }
    }

    // MARK: - Google Sign-In

    private var googleSignInButton: some View {
        Button {
            Task {
                await authViewModel.signInWithGoogle()
            }
        } label: {
            HStack(spacing: 12) {
                // Маленький совет: вместо символа "G" можно скачать официальное
                // SVG лого от Google и использовать Image("google_logo")
                Text("G")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.blue)

                Text("Продолжить с Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }
    
    private var forgotPasswordButton: some View {
        Button {
            authViewModel.clearMessages()
            showResetPassword = true
        } label: {
            Text("Забыли пароль?")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.blue.opacity(0.9))
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }

    private var registerButton: some View {
        VStack(spacing: 6) {
            Text("Ещё нет аккаунта?")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.5))

            Button {
                authViewModel.clearMessages()
                showRegister = true
            } label: {
                Text("Создать аккаунт")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isLoading)
        }
        .padding(.top, 8)
    }

    private func messageRow(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
