import SwiftUI

/// Детали резервной копии: список версий, повторный анализ
/// исходного файла и удаление версии/всей копии.
struct BackupRecordDetailView: View {
    @State private var viewModel: BackupVersionsViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: BackupVersionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recordHeader
                    reparseSection
                    versionsSection
                    deleteSection
                }
                .padding(20)
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.075).ignoresSafeArea())
            .navigationTitle("Резервная копия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task { viewModel.loadVersions() }
            .onChange(of: viewModel.recordDeleted) { _, deleted in
                if deleted { dismiss() }
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
                        .tint(.white)
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .preferredColorScheme(.dark)
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
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("Обновлено: \(viewModel.record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                Label(
                    viewModel.record.storageProvider.name,
                    systemImage: viewModel.record.storageProvider.icon
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())

                Text("Версий: \(viewModel.versions.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.045))
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
                        .foregroundStyle(.white)

                    Text("Проверить исходный файл и создать версию при изменениях")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                if viewModel.isMutating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
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

    // MARK: - Versions

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Версии")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if viewModel.versions.isEmpty {
                Text("Версии пока не загружены.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
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
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(version.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                Text("\(Self.byteFormatter.string(fromByteCount: version.fileSize)) · SHA-256 \(version.checksum.prefix(8))…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
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
        .background(Color.white.opacity(0.04))
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

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
