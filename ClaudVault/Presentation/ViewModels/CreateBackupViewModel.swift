import Foundation
import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class CreateBackupViewModel {

    // MARK: - Dependencies

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let createBackupWithUpload: CreateBackupWithUploadUseCase

    // MARK: - State

    var errorMessage: String?
    var isProgressing = false
    var isCompleted = false
    var uploadProgress: Double = 0

    private(set) var selectedFileName: String?
    private(set) var selectedFileURL: URL?
    private(set) var fileSize: Int64?
    private(set) var checksum: String?

    // MARK: - Initialization

    init(
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        createBackupWithUpload: CreateBackupWithUploadUseCase
    ) {
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.createBackupWithUpload = createBackupWithUpload
    }

    // MARK: - Select File

    func progressFile(at url: URL) {
        isProgressing = true
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0

        selectedFileName = nil
        selectedFileURL = nil
        fileSize = nil
        checksum = nil

        defer {
            isProgressing = false
        }

        do {
            let result = try fileAccessRepository.withAccess(to: url) {
                accessibleURL in

                let hash = try fileHasher.sha256(of: accessibleURL)

                let resourceValues = try accessibleURL.resourceValues(
                    forKeys: [.fileSizeKey]
                )

                let size = Int64(resourceValues.fileSize ?? 0)

                return (hash, size)
            }

            selectedFileName = url.lastPathComponent
            selectedFileURL = url
            checksum = result.0
            fileSize = result.1

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Backup

    /// Создаёт реальную резервную копию: SHA-256 → загрузка в Google Drive
    /// → сохранение метаданных версии. Прогресс загрузки отображается
    /// в `uploadProgress` (0...1).
    func createBackup() async {
        guard let sourceURL = selectedFileURL,
              let selectedFileName else {
            errorMessage = "Сначала выберите файл."
            return
        }

        isProgressing = true
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0

        defer {
            isProgressing = false
        }

        do {
            _ = try await createBackupWithUpload.execute(
                fileName: selectedFileName,
                sourceIdentifier: sourceURL.path,
                fileURL: sourceURL,
                parentFolderID: nil
            ) { [weak self] fraction in
                Task { @MainActor in
                    self?.uploadProgress = fraction
                }
            }

            isCompleted = true
            uploadProgress = 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        selectedFileName = nil
        selectedFileURL = nil
        fileSize = nil
        checksum = nil
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0
    }
}


struct CreateBackupView: View {
    @State private var viewModel: CreateBackupViewModel
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    init(
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        createBackupWithUpload: CreateBackupWithUploadUseCase,
        onCreated: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: CreateBackupViewModel(
                fileAccessRepository: fileAccessRepository,
                fileHasher: fileHasher,
                createBackupWithUpload: createBackupWithUpload
            )
        )

        self.onCreated = onCreated
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
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

                    viewModel.progressFile(at: url)

                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
        .preferredColorScheme(.dark)
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
                        Text(ByteCountFormatter.string(
                            fromByteCount: fileSize,
                            countStyle: .file
                        ))
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
