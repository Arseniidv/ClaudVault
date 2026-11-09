import SwiftUI

struct SettingsFooterView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("CLOUDVAULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.primary.opacity(0.4))

            Text("Версия 1.0.0")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.35))

            Text("Резервное копирование с контролем целостности")
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
