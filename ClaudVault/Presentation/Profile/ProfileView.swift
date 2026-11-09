
import SwiftUI

struct ProfileView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var viewModel: ProfileViewModel

    init(authViewModel: AuthViewModel) {
        _authViewModel = ObservedObject(wrappedValue: authViewModel)
        _viewModel = State(
            wrappedValue: ProfileViewModel(authViewModel: authViewModel)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeader
                profileInformation
                accountSection
                storageSection
            }
            .padding(20)
        }
        .background(
            AppColors.background
                .ignoresSafeArea()
        )
        .navigationTitle("Профиль")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(
            "Профиль обновлён",
            isPresented: $viewModel.showSaveConfirmation
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 86))
                .foregroundStyle(.cyan)

            VStack(spacing: 5) {
                Text(viewModel.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(viewModel.accountEmail)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.5))
            }

            Text(viewModel.plan.uppercased() + " PLAN")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Profile Information

    private var profileInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Личная информация")
            VStack(spacing: 14) {
                profileField(
                    title: "Имя",
                    value: $viewModel.editableName
                )
                profileField(
                    title: "Электронная почта",
                    value: .constant(viewModel.accountEmail),
                    isEditable: false
                )
            }
            .padding(16)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16))  
            if viewModel.isEditing {
                HStack(spacing: 12) {
                    Button("Отмена") {
                        viewModel.cancelEditing()
                    }
                    .disabled(authViewModel.isLoading)
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Сохранить") {
                        Task { await viewModel.saveProfile() }
                    }
                    .disabled(authViewModel.isLoading)
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .background(Color.cyan)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .font(.system(size: 14, weight: .semibold))
            } else {
                Button {
                    viewModel.startEditing()
                } label: {
                    Label("Редактировать профиль", systemImage: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundStyle(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            sectionTitle("Аккаунт")

            VStack(spacing: 0) {
                informationRow(
                    title: "Тип подписки",
                    value: viewModel.plan,
                    icon: "crown"
                )

                Divider()
                    .overlay(Color.primary.opacity(0.08))

                informationRow(
                    title: "Статус аккаунта",
                    value: viewModel.accountStatus,
                    icon: "checkmark.shield"
                )
            }
            .padding(16)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            sectionTitle("Хранилище")

            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CloudVault")
                        .foregroundStyle(AppColors.textPrimary)
                        .font(.system(size: 14, weight: .semibold))

                    Text("Управление резервными копиями")
                        .foregroundStyle(.primary.opacity(0.5))
                        .font(.system(size: 12))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .padding(16)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Components

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
    }

    private func profileField(
        title: String,
        value: Binding<String>,
        isEditable: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.5))

            if isEditable && viewModel.isEditing {
                TextField(title, text: value)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(
                        title == "Имя" ? .words : .never
                    )
                    #endif
                    .autocorrectionDisabled()
            } else {
                Text(value.wrappedValue)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func informationRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {

            Image(systemName: icon)
                .foregroundStyle(.cyan)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(.primary.opacity(0.7))
                .font(.system(size: 14))

            Spacer()

            Text(value)
                .foregroundStyle(AppColors.textPrimary)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 10)
    }
}
