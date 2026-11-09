
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif

struct ResetPasswordView: View {

    let authViewModel: AuthViewModel

    @State private var showMailUnavailableAlert = false
    @State private var isMailPresented = false

    let supportEmail = "support@cloudvault.app"

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                header

                AuthTextField(
                    title: "Email",
                    placeholder: "example@mail.com",
                    systemImage: "envelope",
                    text: $email
                )

                if authViewModel.isResetCodeSent {
                    codeSection
                }

                if let error = authViewModel.errorMessage {
                    messageRow(text: error, color: .red)
                }

                if let success = authViewModel.successMessage {
                    messageRow(text: success, color: .green)
                }

                if authViewModel.isResetCodeSent {
                    confirmButton
                    resendButton
                } else {
                    sendButton
                }

                supportButton
                backButton
            }
            .padding(24)
        }
        .background {
            AppColors.background
                .ignoresSafeArea()
        }
        .navigationTitle("Сброс пароля")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            authViewModel.clearMessages()
        }
        .sheet(isPresented: $isMailPresented) {
            MailComposer(
                recipient: supportEmail,
                subject: "Поддержка CloudVault",
                messageBody: """
                Здравствуйте!

                Мне необходима помощь с восстановлением доступа к аккаунту CloudVault.

                Email аккаунта: \(email)
                """
            )
        }
        .alert(
            "Почта недоступна",
            isPresented: $showMailUnavailableAlert
        ) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("На устройстве не настроена отправка электронной почты.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.blue.opacity(0.9))
                .padding(.top, 24)

            Text("Восстановление доступа")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(authViewModel.isResetCodeSent
                 ? "Введите 6-значный код из письма и придумайте новый пароль."
                 : "Мы отправим код для сброса пароля на указанный адрес через Gmail.")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step 2: code + new password

    private var codeSection: some View {
        VStack(spacing: 16) {
            AuthTextField(
                title: "Код из письма",
                placeholder: "000000",
                systemImage: "number",
                text: $resetCode
            )

            AuthPasswordField(
                title: "Новый пароль",
                placeholder: "Минимум 12 символов",
                password: $newPassword
            )

            AuthPasswordField(
                title: "Повторите пароль",
                placeholder: "Введите пароль ещё раз",
                password: $confirmPassword
            )
        }
    }

    // MARK: - Actions

    private var sendButton: some View {
        Button {
            Task {
                await authViewModel.requestPasswordResetCode(email: email)
            }
        } label: {
            HStack(spacing: 10) {
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(AppColors.onAccent)
                } else {
                    Text("Отправить код")
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

    private var confirmButton: some View {
        Button {
            guard newPassword == confirmPassword else {
                authViewModel.errorMessage = "Пароли не совпадают."
                return
            }
            Task {
                await authViewModel.confirmPasswordReset(
                    email: email,
                    code: resetCode,
                    newPassword: newPassword
                )
            }
        } label: {
            HStack(spacing: 10) {
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(AppColors.onAccent)
                } else {
                    Text("Сохранить новый пароль")
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

    private var resendButton: some View {
        Button {
            resetCode = ""
            newPassword = ""
            confirmPassword = ""
            Task {
                await authViewModel.requestPasswordResetCode(email: email)
            }
        } label: {
            Text("Отправить код повторно")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.blue.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }

    // MARK: - Support Button

    private var supportButton: some View {
        Button {
            isMailPresented = true
        } label: {
            Label(
                "Связаться с поддержкой",
                systemImage: "envelope"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Вернуться ко входу")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }

    // MARK: - Message Row

    private func messageRow(
        text: String,
        color: Color
    ) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
