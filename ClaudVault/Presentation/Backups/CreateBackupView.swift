import SwiftUI
import UniformTypeIdentifiers

struct CreateBackupView: View {
    @State private var viewModel: CreateBackupViewModel
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    private let initialFileURL: URL?
    /// Автоматически открыть системный выбор файла при появлении
    /// (deep link из виджета: `claudvault://backup/new?mode=file`).
    private let autoOpenImporter: Bool

    init(
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        createBackupWithUpload: CreateBackupWithUploadUseCase,
        availableProviders: [StorageProviderType] = [.googleDrive],
        initialFileURL: URL? = nil,
        autoOpenImporter: Bool = false,
        onCreated: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreateBackupViewModel(
                fileAccessRepository: fileAccessRepository,
                fileHasher: fileHasher,
                createBackupWithUpload: createBackupWithUpload,
                availableProviders: availableProviders
            )
        )

        self.initialFileURL = initialFileURL
        self.autoOpenImporter = autoOpenImporter
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    providerSection
                    fileSelectionSection
                    if let fileName = viewModel.selectedFileName {
                        selectedFileSection(fileName: fileName)
                    }
                    if viewModel.isProgressing && !viewModel.isCompleted {
                        progressSection
                    }
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                    if viewModel.isCompleted {
                        successSection
                    }
                    Spacer(minLength: 10)
                    createButton
                }
                .padding(24)
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.075))
            .navigationTitle("Новая резервная копия")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    closeButton
                }
                #endif
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        return
                    }
                    Task {
                        await viewModel.progressFile(at: url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Файл, выбранный заранее (например, PDF из сканера документов).
            if let initialFileURL {
                await viewModel.progressFile(at: initialFileURL)
            } else if autoOpenImporter {
                // Deep link из виджета — сразу показываем выбор файла.
                isImporterPresented = true
            }
        }
    }

    private var closeButton: some View {
        Button("Закрыть") {
            dismiss()
        }
        .foregroundStyle(.white)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Создание резервной копии")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)

            Text("Файл будет загружен в подключённое облачное хранилище.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Выбор облака-приёмника: файл загружается в выбранное
    /// подключённое хранилище (Google Drive, Dropbox, OneDrive).
    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Облачное хранилище")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if viewModel.availableProviders.count > 1 {
                HStack(spacing: 10) {
                    ForEach(viewModel.availableProviders) { provider in
                        let isSelected = viewModel.selectedProvider == provider
                        Button {
                            viewModel.selectedProvider = provider
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: provider.icon)
                                Text(provider.name)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                isSelected
                                    ? Color.blue.opacity(0.85)
                                    : Color.white.opacity(0.05)
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(
                                        isSelected
                                            ? Color.blue
                                            : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isProgressing)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.selectedProvider.icon)
                    Text(viewModel.selectedProvider.name)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            }
        }
    }

    private var fileSelectionSection: some View {
        Button {
            isImporterPresented = true
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        Color(red: 0.48, green: 0.65, blue: 1)
                    )
                Text(
                    viewModel.selectedFileName == nil
                    ? "Выбрать файл"
                    : "Выбрать другой файл"
                )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

                Text("Откроется системное приложение «Файлы»")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        Color.white.opacity(0.09),
                        style: StrokeStyle(lineWidth: 1, dash: [6])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProgressing)
    }

    private func selectedFileSection(fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Выбранный файл")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 5) {
                    Text(fileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let fileSize = viewModel.fileSize {
                        Text(ByteFormatting.string(fromByteCount: fileSize))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(16)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text("Имя файла")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                TextField("Имя файла", text: $viewModel.editableFileName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(viewModel.isProgressing)
            }

            if let checksum = viewModel.checksum {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SHA-256")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(checksum)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Загрузка в облако")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text("\(Int(viewModel.uploadProgress * 100))%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(Color.blue)
                        .frame(
                            width: geometry.size.width *
                                min(max(viewModel.uploadProgress, 0), 1)
                        )
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var successSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Резервная копия успешно создана")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var createButton: some View {
        Button {
            Task {
                await viewModel.createBackup()

                if viewModel.isCompleted {
                    onCreated()
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isProgressing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus.circle.fill")
                }

                Text(
                    viewModel.isProgressing
                    ? "Создание..."
                    : "Создать резервную копию"
                )
                .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                viewModel.selectedFileURL == nil
                ? Color.gray.opacity(0.3)
                : Color.blue
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(
            viewModel.selectedFileURL == nil ||
            viewModel.isProgressing ||
            viewModel.isCompleted
        )
    }
}
