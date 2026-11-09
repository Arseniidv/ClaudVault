#if os(macOS)
import Foundation
import ClaudVaultDomain

/// Связывает Radial Menu с зависимостями приложения при старте.
/// Собирает `FileActionContext` из AppDependencies, регистрирует
/// обработчики действий, включает глобальную клавишу и Services.
enum RadialMenuAppIntegration {

    /// Ключи настроек Radial Menu (UserDefaults).
    enum Keys {
        /// Включена ли глобальная горячая клавиша. По умолчанию включена.
        static let hotKeyEnabled = "radialMenuHotKeyEnabled"
        /// Пресет сочетания (`RadialHotKeyPreset.rawValue`).
        /// По умолчанию ⌥Space.
        static let hotKeyPreset = "radialMenuHotkeyPreset"
        /// Extended Mode: чтение выделения чужих приложений
        /// через Accessibility API. По умолчанию выключен.
        static let extendedSelection = "radialMenuExtendedSelection"
        /// Кнопка «+» в меню: добавление файлов к выделению.
        /// При включении NSOpenPanel разрешает выбор нескольких
        /// файлов сразу. По умолчанию включено.
        static let multiFileSelection = "radialMenuMultiFileSelection"
    }

    @MainActor
    static func configure(dependencies: AppDependencies) {
        let downloadsDirectory = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")

        let repositories: [StorageProviderType: CloudStorageRepository] = [
            .googleDrive: dependencies.cloudStorageRepository,
            .dropbox: dependencies.dropboxRepository,
            .oneDrive: dependencies.oneDriveRepository
        ]

        let context = FileActionContext(
            backupMetadataRepository: dependencies.backupMetadataRepository,
            repositories: repositories,
            createBackupWithUpload: dependencies.createBackupWithUpload,
            transferBackupToProvider: dependencies.transferBackupToProvider,
            supportedProviders: StoragesViewModel.supportedProviders,
            downloadsDirectory: downloadsDirectory,
            storagesViewModel: dependencies.storagesViewModel
        )

        let defaults = UserDefaults.standard
        RadialMenuCoordinator.shared.configure(
            context: context,
            extendedSelectionEnabled: defaults.bool(
                forKey: Keys.extendedSelection
            ),
            multiFileSelectionEnabled: defaults.object(
                forKey: Keys.multiFileSelection
            ) as? Bool ?? true
        )

        // Глобальная клавиша (Carbon RegisterEventHotKey).
        GlobalHotKeyManager.shared.onTriggered = {
            Task { @MainActor in
                await RadialMenuCoordinator.shared.hotKeyInvoked()
            }
        }
        applyHotKeySettings(from: defaults)

        // Уборка возможных протухших запросов Finder Sync Extension.
        AppGroupRequestStore.cleanupExpiredRequests()
    }

    /// Текущий пресет хоткея из настроек.
    static var hotKeyPreset: RadialHotKeyPreset {
        RadialHotKeyPreset(
            rawValue: UserDefaults.standard.string(
                forKey: Keys.hotKeyPreset
            ) ?? ""
        ) ?? .optionSpace
    }

    /// Включена ли глобальная клавиша.
    static var isHotKeyEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.hotKeyEnabled)
            as? Bool ?? true
    }

    private static func applyHotKeySettings(
        from defaults: UserDefaults = .standard
    ) {
        GlobalHotKeyManager.shared.apply(
            enabled: defaults.object(forKey: Keys.hotKeyEnabled)
                as? Bool ?? true,
            preset: hotKeyPreset
        )
    }

    /// Вызывается из SettingsView при переключении хоткея.
    @MainActor
    static func setHotKeyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.hotKeyEnabled)
        applyHotKeySettings()
    }

    /// Вызывается из SettingsView при смене пресета сочетания.
    @MainActor
    static func setHotKeyPreset(_ preset: RadialHotKeyPreset) {
        UserDefaults.standard.set(
            preset.rawValue,
            forKey: Keys.hotKeyPreset
        )
        applyHotKeySettings()
    }

    /// Вызывается из SettingsView при переключении Extended Mode.
    @MainActor
    static func setExtendedSelectionEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.extendedSelection)
        RadialMenuCoordinator.shared.setExtendedSelectionEnabled(enabled)
    }

    /// Вызывается из SettingsView при переключении множественного
    /// добавления файлов.
    @MainActor
    static func setMultiFileSelectionEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(
            enabled,
            forKey: Keys.multiFileSelection
        )
        RadialMenuCoordinator.shared
            .setMultiFileSelectionEnabled(enabled)
    }
}
#endif
