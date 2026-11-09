import SwiftUI

struct SearchSectionView: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(Color.primary.opacity(0.65))

            TextField("Поиск по всем хранилищам", text: $searchText)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

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
        .background(Color.primary.opacity(0.055))
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.large)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
