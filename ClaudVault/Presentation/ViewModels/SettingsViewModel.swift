
import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    // MARK: - Settings

    var automaticBackupEnabled = false
    var notificationsEnabled = true
    var integrityCheckEnabled = true
    var biometricLockEnabled = false

    // MARK: - UI State

    var showAbout = false

    // MARK: - Initialization

    init() {
        loadSettings()
    }

    // MARK: - Load Settings

    private func loadSettings() {
        let defaults = UserDefaults.standard

        automaticBackupEnabled = defaults.bool(
            forKey: "automaticBackupEnabled"
        )

        notificationsEnabled = defaults.object(
            forKey: "notificationsEnabled"
        ) as? Bool ?? true

        integrityCheckEnabled = defaults.object(
            forKey: "integrityCheckEnabled"
        ) as? Bool ?? true

        biometricLockEnabled = defaults.bool(
            forKey: "biometricLockEnabled"
        )
    }

    // MARK: - Save Settings

    private func saveSettings() {
        let defaults = UserDefaults.standard

        defaults.set(
            automaticBackupEnabled,
            forKey: "automaticBackupEnabled"
        )

        defaults.set(
            notificationsEnabled,
            forKey: "notificationsEnabled"
        )

        defaults.set(
            integrityCheckEnabled,
            forKey: "integrityCheckEnabled"
        )

        defaults.set(
            biometricLockEnabled,
            forKey: "biometricLockEnabled"
        )
    }

    // MARK: - Update Settings

    func updateSettings() {
        saveSettings()
    }
}
