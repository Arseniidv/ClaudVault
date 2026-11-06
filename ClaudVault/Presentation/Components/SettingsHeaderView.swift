import SwiftUI

struct SettingsHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLOUDVAULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Color(red: 0.48, green: 0.65, blue: 1))

            Text("Настройки")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            Text("Управление приложением и безопасностью")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
