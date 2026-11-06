
import SwiftUI

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel

    @State private var automaticBackupEnabled = false
    @State private var notificationsEnabled = true
    @State private var integrityCheckEnabled = true
    @AppStorage("biometricLockEnabled")
    private var biometricLockEnabled = false
    @AppStorage("twoFactorEnabled")
    private var twoFactorEnabled = false
    @State private var otpCode = ""
    @State private var showAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHeaderView()

                SettingsProfileView(
                    accountName: authViewModel.currentUser?.displayName,
                    accountEmail: authViewModel.currentUser?.email
                )

                settingsSection(
                    title: "Резервное копирование",
                    icon: "externaldrive"
                ) {
                    SettingsToggleRow(
                        title: "Автоматическое копирование",
                        subtitle: "Создавать резервные копии автоматически",
                        icon: "arrow.clockwise",
                        isOn: $automaticBackupEnabled
                    )
                }

                settingsSection(
                    title: "Безопасность",
                    icon: "lock.shield"
                ) {
                    SettingsToggleRow(
                        title: "Проверка целостности",
                        subtitle: "Проверять файлы после копирования",
                        icon: "checkmark.shield",
                        isOn: $integrityCheckEnabled
                    )

                    SettingsToggleRow(
                        title: "Биометрическая защита",
                        subtitle: "Защита приложения с помощью Face ID",
                        icon: "faceid",
                        isOn: $biometricLockEnabled
                    )
                    emailVerificationRow

                    SettingsToggleRow(
                        title: "Двухфакторная верификация",
                        subtitle: twoFactorEnabled
                            ? "Включена — код при подключении облаков"
                            : "Код из email для критических операций",
                        icon: "person.2.shield",
                        isOn: Binding(
                            get: { twoFactorEnabled },
                            set: { newValue in
                                if newValue {
                                    Task { await authViewModel.enableTwoFactor() }
                                } else {
                                    authViewModel.disableTwoFactor()
                                    twoFactorEnabled = false
                                }
                            }
                        )
                    )
                }

                settingsSection(
                    title: "Уведомления",
                    icon: "bell"
                ) {
                    SettingsToggleRow(
                        title: "Push-уведомления",
                        subtitle: "Получать уведомления о синхронизации",
                        icon: "bell.badge",
                        isOn: $notificationsEnabled
                    )
                }

                Button {
                    showAbout = true
                } label: {
                    Label("О приложении", systemImage: "info.circle")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if authViewModel.currentUser != nil {
                    Button {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 17))
                            }

                            Text("Выйти из аккаунта")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(authViewModel.isLoading)
                }

                SettingsFooterView()
            }
            .padding(20)
        }
        .background(Color(red: 0.035, green: 0.045, blue: 0.075))
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .alert("CloudVault", isPresented: $showAbout) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text("CloudVault — приложение для резервного копирования и синхронизации файлов.")
        }
        .alert("Ошибка", isPresented: Binding(
            get: { authViewModel.errorMessage != nil },
            set: { if !$0 { authViewModel.clearMessages() } }
        )) {
            Button("OK", role: .cancel) { authViewModel.clearMessages() }
        } message: {
            Text(authViewModel.errorMessage ?? "")
        }
        .alert("Готово", isPresented: Binding(
            get: { authViewModel.successMessage != nil },
            set: { if !$0 { authViewModel.clearMessages() } }
        )) {
            Button("OK", role: .cancel) { authViewModel.clearMessages() }
        } message: {
            Text(authViewModel.successMessage ?? "")
        }
        .alert("Код подтверждения", isPresented: $authViewModel.isOTPEntryPresented) {
            TextField("000000", text: $otpCode)
                .keyboardType(.numberPad)

            Button("Подтвердить") {
                let code = otpCode
                otpCode = ""
                Task { await authViewModel.confirmTwoFactorCode(code) }
            }
            .disabled(otpCode.trimmingCharacters(in: .whitespaces).count != 6)

            Button("Отмена", role: .cancel) {
                otpCode = ""
                authViewModel.isOTPEntryPresented = false
            }
        } message: {
            Text("Введите 6-значный код из письма, отправленного на вашу почту.")
        }
    }

    /// Подтверждение email через ссылку из письма (passwordless Firebase).
    private var emailVerificationRow: some View {
        let isVerified = authViewModel.currentUser?.emailVerified ?? false
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.shield")
                    .font(.system(size: 17))
                    .foregroundStyle(.cyan)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Подтверждение почты")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)

                    Text(isVerified
                         ? "Почта подтверждена"
                         : "Подтвердите email ссылкой из письма")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if isVerified {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await authViewModel.sendEmailVerificationLink() }
                    } label: {
                        Text("Отправить")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.cyan)
                            .clipShape(Capsule())
                    }
                    .disabled(authViewModel.isLoading)
                }
            }
            .padding(14)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.cyan)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(.cyan)
        }
        .padding(14)
    }
}

