import SwiftUI

struct AddBackupButton: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(
                        colors: [
                            Color.blue,
                            Color.cyan
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(
                    color: Color.blue.opacity(0.35),
                    radius: 12,
                    x: 0,
                    y: 5
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Создать резервную копию")
    }
}
