import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)

            TextField("Поиск файлов...", text: $searchText)
                .font(AppTypography.body)
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(Color.white.opacity(0.055))
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
