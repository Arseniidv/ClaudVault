import SwiftUI

struct FilterSelectorView: View {

    /// nil означает "Все" — без фильтрации по провайдеру.
    @Binding var selectedProvider: StorageProviderType?

    /// Провайдеры, для которых показываются чипсы.
    /// nil — показать все известные провайдеры.
    var providers: [StorageProviderType]? = nil

    /// Порядок чипсов соответствует макету.
    private static let allProviders: [StorageProviderType] = [
        .googleDrive,
        .oneDrive,
        .iCloud,
        .dropbox,
        .local
    ]

    private var visibleProviders: [StorageProviderType] {
        providers ?? Self.allProviders
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                chip(title: "Все", tint: nil, isSelected: selectedProvider == nil) {
                    selectedProvider = nil
                }

                ForEach(visibleProviders) { provider in
                    chip(
                        title: provider.name,
                        tint: provider.tint,
                        isSelected: selectedProvider == provider
                    ) {
                        selectedProvider = provider
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        .padding(.horizontal, -AppSpacing.screenHorizontal)
    }

    @ViewBuilder
    private func chip(
        title: String,
        tint: Color?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            HStack(spacing: 6) {
                if !isSelected, let tint {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .black : .white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : Color.primary.opacity(0.15),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FilterSelectorView(selectedProvider: .constant(nil))
        .background(AppColors.background)
}
