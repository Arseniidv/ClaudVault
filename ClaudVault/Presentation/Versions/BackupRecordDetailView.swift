import SwiftUI
import ClaudVaultDomain

/// Детали резервной копии: список версий, повторный анализ
/// исходного файла и удаление версии/всей копии.
struct BackupRecordDetailView: View {
    @State private var viewModel: BackupVersionsViewModel
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss

    init(viewModel: BackupVersionsViewModel) {
        _viewModel = State(initialValue: viewModel)
        _renameText = State(initialValue: viewModel.record.fileName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recordHeader
                    renameSection
                    reparseSection
                    transferSection
                    versionsSection
                    deleteSection
                }
                .padding(20)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Резервная копия")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                #endif
            }
            .task { viewModel.loadVersions() }
            .onChange(of: viewModel.recordDeleted) { _, deleted in
                if deleted { dismiss() }
            }
            // После успешного переименования синхронизируем поле
            // с фактическим именем (могло дописаться расширение).
            .onChange(of: viewModel.record.fileName) { _, newName in
                renameText = newName
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Готово",
                isPresented: Binding(
                    get: { viewModel.infoMessage != nil },
                    set: { if !$0 { viewModel.infoMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.infoMessage = nil }
            } message: {
                Text(viewModel.infoMessage ?? "")
            }
            .overlay {
                if viewModel.isMutating {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Record header

    private var recordHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 26))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.record.fileName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)

                    Text("Обновлено: \(viewModel.record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                Label(
                    viewModel.record.storageProvider.name,
                    systemImage: viewModel.record.storageProvider.icon
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.07))
                .clipShape(Capsule())

                Text("Версий: \(viewModel.versions.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Rename

    /// Переименование копии: меняет имя в приложении и в облаке
    /// без создания новой версии или повторной загрузки.
    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Имя файла")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: 10) {
                TextField("Имя файла", text: $renameText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(12)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(viewModel.isMutating)

                Button("Сохранить") {
                    viewModel.renameRecord(to: renameText)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(
                    viewModel.isMutating ||
                    renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Re-parse

    private var reparseSection: some View {
        Button {
            viewModel.reparse()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Повторить анализ")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Проверить исходный файл и создать версию при изменениях")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.55))
                }

                Spacer()

                if viewModel.isMutating {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.4))
                }
            }
            .padding(16)
            .background(Color.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isMutating)
    }

    // MARK: - Transfer to another cloud

    /// Перенос всех версий копии в другое подключённое облако:
    /// «Скопировать» — дубликат в целевом облаке, исходник
    /// остаётся; «Переместить» — исходные объекты удаляются
    /// после проверки приёмника.
    @ViewBuilder
    private var transferSection: some View {
        if !viewModel.transferTargets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Перенос в другое облако")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                if let progress = viewModel.transferProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.blue)
                        Text("Перенос… \(Int(progress * 100))%")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(viewModel.transferTargets) { target in
                        transferTargetRow(target)
                    }
                }
            }
        }
    }

    private func transferTargetRow(_ target: StorageProviderType) -> some View {
        Menu {
            Button {
                viewModel.transferToProvider(target, move: false)
            } label: {
                Label(
                    "Скопировать в \(target.name)",
                    systemImage: "plus.doc.on.doc"
                )
            }
            Button(role: .destructive) {
                viewModel.transferToProvider(target, move: true)
            } label: {
                Label(
                    "Переместить в \(target.name)",
                    systemImage: "arrow.right.doc.on.clipboard"
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: target.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(target.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Все версии копии → \(target.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.55))
                }

                Spacer()

                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .padding(16)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(viewModel.isMutating)
    }

    // MARK: - Versions

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Версии")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            if viewModel.versions.isEmpty {
                Text("Версии пока не загружены.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.versions) { version in
                    versionRow(version)
                }
            }
        }
    }

    private func versionRow(_ version: BackupVersion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16))
                .foregroundStyle(.primary.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(version.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text("\(ByteFormatting.string(fromByteCount: version.fileSize)) · SHA-256 \(version.checksum.prefix(8))…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.deleteVersion(version)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMutating)
            .accessibilityLabel("Удалить версию")
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Delete all

    private var deleteSection: some View {
        Button(role: .destructive) {
            viewModel.deleteRecord()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                Text("Удалить всю резервную копию")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isMutating)
    }
}
