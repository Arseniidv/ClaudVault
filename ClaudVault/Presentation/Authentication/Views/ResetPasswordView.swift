
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

                if let error = authViewModel.errorMessage {
                    messageRow(text: error, color: .red)
                }

                if let success = authViewModel.successMessage {
                    messageRow(text: success, color: .green)
                }

                sendButton
                supportButton
                backButton
            }
            .padding(24)
        }
        .background {
            Color(red: 0.035, green: 0.04, blue: 0.055)
                .ignoresSafeArea()
        }
        .navigationTitle("Сброс пароля")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(.white)

            Text("Мы отправим письмо со ссылкой для смены пароля на указанный адрес.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private var sendButton: some View {
        Button {
            Task {
                await authViewModel.resetPassword(email: email)
            }
        } label: {
            HStack(spacing: 10) {
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Отправить письмо")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
    }

    // MARK: - Support Button (TEST)

    private var supportButton: some View {
        Button {
            print("Support button tapped")
            print("Opening MailComposer sheet...")

            // Временно открываем sheet без проверки почты
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
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
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
