
import SwiftUI

struct SettingsProfileView: View {
    @ObservedObject var authViewModel: AuthViewModel

    private var user: AuthUser? {
        authViewModel.currentUser
    }

    private var isConnected: Bool {
        user != nil
    }

    var body: some View {
        NavigationLink {
            ProfileView(authViewModel: authViewModel)
        } label: {
            HStack(spacing: 14) {

                // Аватар
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(
                            Color(
                                red: 0.48,
                                green: 0.65,
                                blue: 1
                            )
                        )
                }

                // Информация о профиле
                VStack(alignment: .leading, spacing: 5) {
                    Text(user?.resolvedDisplayName ?? "Локальный профиль")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(user?.resolvedEmail ?? "Аккаунт не подключён")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Image(systemName: isConnected
                      ? "checkmark.circle.fill"
                      : "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isConnected
                                     ? .green.opacity(0.9)
                                     : .white.opacity(0.5))
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
