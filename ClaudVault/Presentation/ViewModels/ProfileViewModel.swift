
import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {

    // MARK: - Profile Data

    var name: String = ""
    var email: String = ""
    var plan: String = "Free"
  

    // MARK: - Editing State

    var isEditing = false
    var showSaveConfirmation = false

    private var originalName = ""
    private var originalEmail = ""

    // MARK: - Initialization

    init() {
        loadProfile()
    }

    // MARK: - Profile Management

    func loadProfile() {
        let defaults = UserDefaults.standard
        name = defaults.string(forKey: "profileName") ?? "Пользователь"
        email = defaults.string(forKey: "profileEmail") ?? "user@example.com"
        plan = defaults.string(forKey: "profilePlan") ?? "Free"

        originalName = name
        originalEmail = email
    }

    func startEditing() {
        originalName = name
        originalEmail = email
        isEditing = true
    }

    func saveProfile() {
        let defaults = UserDefaults.standard

        defaults.set(name, forKey: "profileName")
        defaults.set(email, forKey: "profileEmail")

        originalName = name
        originalEmail = email

        isEditing = false
        showSaveConfirmation = true
    }

    func cancelEditing() {
        name = originalName
        email = originalEmail
        isEditing = false
    }

    func resetProfile() {
        name = "Пользователь"
        email = "user@example.com"
        plan = "Free"

        saveProfile()
    }
}

