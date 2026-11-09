
import Foundation
import Observation
import ClaudVaultDomain

@MainActor
@Observable
final class ProfileViewModel {

    private let authViewModel: AuthViewModel

    // MARK: - Editing State

    var isEditing = false
    var showSaveConfirmation = false
    private var draftName = ""

    // MARK: - Initialization

    init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    // MARK: - Profile Data

    var user: AuthUser? {
        authViewModel.currentUser
    }

    var displayName: String {
        user?.resolvedDisplayName ?? "Гость"
    }

    var accountEmail: String {
        user?.resolvedEmail ?? "—"
    }

    var plan: String {
        "Free"
    }

    var accountStatus: String {
        user == nil ? "Гость" : "Активен"
    }

    var editableName: String {
        get { isEditing ? draftName : displayName }
        set { draftName = newValue }
    }

    // MARK: - Editing

    func startEditing() {
        guard user != nil else { return }
        draftName = displayName
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
    }

    func saveProfile() async {
        guard user != nil else { return }

        if await authViewModel.updateProfile(name: draftName) {
            isEditing = false
            showSaveConfirmation = true
        }
    }
}
