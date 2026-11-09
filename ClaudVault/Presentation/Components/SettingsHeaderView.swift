import SwiftUI

struct SettingsHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLOUDVAULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(AppColors.accent)

            Text("Настройки")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Управление приложением и безопасностью")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
