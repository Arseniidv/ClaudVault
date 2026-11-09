
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    var deviceTransferCoordinator: DeviceTransferCoordinator?

    @State private var automaticBackupEnabled = false
    @State private var notificationsEnabled = true
    @State private var integrityCheckEnabled = true
    @AppStorage("biometricLockEnabled")
    private var biometricLockEnabled = false
    #if os(macOS)
    private let biometricLockSubtitle = "Защита приложения с помощью Touch ID"
    private let biometricLockIcon = "touchid"
    #else
    private let biometricLockSubtitle = "Защита приложения с помощью Face ID"
    private let biometricLockIcon = "faceid"
    #endif
    #if os(macOS)
    /// Radial Menu: глобальная клавиша, Extended Mode
    /// (Accessibility API для чтения выделения чужих приложений)
    /// и множественное добавление файлов.
    @AppStorage(RadialMenuAppIntegration.Keys.hotKeyEnabled)
    private var radialHotKeyEnabled = true
    @AppStorage(RadialMenuAppIntegration.Keys.hotKeyPreset)
    private var radialHotKeyPresetRaw = RadialHotKeyPreset
        .optionSpace.rawValue
    @AppStorage(RadialMenuAppIntegration.Keys.extendedSelection)
    private var radialExtendedSelection = false
    @AppStorage(RadialMenuAppIntegration.Keys.multiFileSelection)
    private var radialMultiFileSelection = true
    #endif
    /// 2FA-флаг хранится per-owner — ключ вычисляется при
    /// создании view (SettingsView пересоздаётся при смене
    /// пользователя, т.к. живёт внутри mainAppView).
    @AppStorage private var twoFactorEnabled: Bool
    @State private var otpCode = ""
    @State private var showAbout = false

    init(
        authViewModel: AuthViewModel,
        deviceTransferCoordinator: DeviceTransferCoordinator? = nil
    ) {
        _authViewModel = ObservedObject(wrappedValue: authViewModel)
        self.deviceTransferCoordinator = deviceTransferCoordinator
        _twoFactorEnabled = AppStorage(
            wrappedValue: false,
            OTPService.scopedKey(OTPService.twoFactorEnabledKey)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHeaderView()

                SettingsProfileView(authViewModel: authViewModel)

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
                        subtitle: biometricLockSubtitle,
                        icon: biometricLockIcon,
                        isOn: $biometricLockEnabled
                    )
                    emailVerificationRow

                    if let deviceTransferCoordinator {
                        Button {
                            deviceTransferCoordinator.open()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Перенос на другое устройство")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)

                                    Text("QR-код для переноса облачных подключений")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary.opacity(0.5))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.35))
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                    }

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

                #if os(macOS)
                settingsSection(
                    title: "Radial Menu",
                    icon: "circle.grid.3x3"
                ) {
                    SettingsToggleRow(
                        title: "Горячая клавиша",
                        subtitle: radialHotKeySubtitle,
                        icon: "keyboard",
                        isOn: Binding(
                            get: { radialHotKeyEnabled },
                            set: { newValue in
                                radialHotKeyEnabled = newValue
                                RadialMenuAppIntegration
                                    .setHotKeyEnabled(newValue)
                            }
                        )
                    )

                    hotKeyPresetRow

                    SettingsToggleRow(
                        title: "Выделение в других приложениях",
                        subtitle: "⌥Space читает выбранные файлы через Accessibility API (Finder, Preview, браузеры)",
                        icon: "hand.raised",
                        isOn: Binding(
                            get: { radialExtendedSelection },
                            set: { newValue in
                                radialExtendedSelection = newValue
                                RadialMenuAppIntegration
                                    .setExtendedSelectionEnabled(newValue)
                                if newValue,
                                   !AccessibilityPermissionManager.isTrusted {
                                    AccessibilityPermissionManager
                                        .requestAccess()
                                }
                            }
                        )
                    )

                    SettingsToggleRow(
                        title: "Добавление файлов",
                        subtitle: "Кнопка «+» в меню — выбор файлов с диска, несколько сразу",
                        icon: "plus.rectangle.on.rectangle",
                        isOn: Binding(
                            get: { radialMultiFileSelection },
                            set: { newValue in
                                radialMultiFileSelection = newValue
                                RadialMenuAppIntegration
                                    .setMultiFileSelectionEnabled(newValue)
                            }
                        )
                    )
                }
                #endif

                aboutButton

                if authViewModel.currentUser != nil {
                    signOutButton
                }

                SettingsFooterView()
            }
            .padding(20)
        }
        .background(AppColors.background)
        .navigationTitle("Настройки")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

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

    #if os(macOS)
    /// Подзаголовок строки хоткея: выбранный пресет
    /// и состояние регистрации Carbon-обработчика
    /// (комбинация может быть занята).
    private var radialHotKeySubtitle: String {
        let preset = RadialHotKeyPreset(
            rawValue: radialHotKeyPresetRaw
        ) ?? .optionSpace
        guard radialHotKeyEnabled else { return "Выключена" }
        if !GlobalHotKeyManager.shared.isRegistered {
            return "\(preset.title) занята другим приложением"
        }
        if preset.systemConflict != nil {
            return "\(preset.title) — возможен конфликт с macOS"
        }
        return "\(preset.title) — вызвать Radial Menu"
    }

    /// Строка выбора пресета сочетания клавиш.
    private var hotKeyPresetRow: some View {
        let preset = RadialHotKeyPreset(
            rawValue: radialHotKeyPresetRaw
        ) ?? .optionSpace
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.system(size: 17))
                .foregroundStyle(.cyan)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("Сочетание клавиш")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Вызов Radial Menu")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
            }

            Spacer()

            Menu {
                ForEach(RadialHotKeyPreset.allCases) { option in
                    Button {
                        radialHotKeyPresetRaw = option.rawValue
                        RadialMenuAppIntegration
                            .setHotKeyPreset(option)
                    } label: {
                        if option == preset {
                            Label(option.title, systemImage: "checkmark")
                        } else if option.systemConflict != nil {
                            Label(
                                "\(option.title) ⚠",
                                systemImage: "exclamationmark.triangle"
                            )
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text(
                    preset.systemConflict != nil
                        ? "\(preset.title) ⚠"
                        : preset.title
                )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.cyan)
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            }

            if let conflict = preset.systemConflict {
                Label(
                    "Это сочетание может конфликтовать с macOS: "
                    + conflict + ". Вызов Radial Menu может не срабатывать.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
            }
        }
        .padding(14)
    }
    #endif

    private var aboutButton: some View {
        Button {
            showAbout = true
        } label: {
            Label("О приложении", systemImage: "info.circle")
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var signOutButton: some View {
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
                        .foregroundStyle(AppColors.textPrimary)

                    Text(isVerified
                         ? "Почта подтверждена"
                         : "Подтвердите email ссылкой из письма")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.5))
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
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.05))
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
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(.cyan)
        }
        .padding(14)
    }
}

