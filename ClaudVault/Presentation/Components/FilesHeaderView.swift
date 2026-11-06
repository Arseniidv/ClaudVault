import SwiftUI

struct FilesHeaderView: View {
    @Binding var selectedSort: RecentFilesView.SortOption
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("CLOUDVAULT")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Color.white.opacity(0.65))

                Text("Все файлы")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Menu {
                ForEach(RecentFilesView.SortOption.allCases) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        if selectedSort == option {
                            Label(
                                option.rawValue,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.055))
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadius.large)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.large)
                            .stroke(
                                Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    }
            }
        }
    }
}
