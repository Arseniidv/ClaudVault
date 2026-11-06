import SwiftUI
import UniformTypeIdentifiers

struct StoragesView: View {
    let viewModel: StoragesViewModel

    @State private var showingAddStorage = false
    @State private var showingFilePicker = false
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var pendingTransferFile: CloudFile?

    private var providers: [StorageProvider] {
        viewModel.connectedStorageProviders
    }

    private var totalUsed: Double {
        providers.reduce(0) { $0 + $1.usedStorage }
    }

    private var totalCapacity: Double {
        providers.reduce(0) { $0 + $1.totalStorage }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summarySection
                providersSection
                addStorageButton
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.055))
        .navigationTitle("Хранилища")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddStorage) {
            addStorageSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.otpChallengeProvider != nil },
            set: { if !$0 { viewModel.cancelOTPChallenge() } }
        )) {
            otpChallengeSheet
        }
    }

    // MARK: - OTP challenge

    /// Шит ввода 6-значного кода — показывается, когда 2FA включена
    /// и нужно подтвердить подключение нового облака.
    private var otpChallengeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text("Подтверждение кодом")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("Для подключения нового хранилища введите 6-значный код, отправленный на вашу почту.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))

                if viewModel.isOTPRequestRunning {
                    HStack(spacing: 10) {
                        ProgressView().tint(.cyan)
                        Text("Отправляем код…")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    OTPCodeField { code in
                        Task { await viewModel.submitOTPCodeForPendingConnect(code) }
                    }
                }

                if let kind = viewModel.otpChallengeProvider,
                   let error = viewModel.state(for: kind).errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await viewModel.resendOTPCode() }
                } label: {
                    Text("Отправить код повторно")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .disabled(viewModel.isOTPRequestRunning)

                Button("Отмена") {
                    viewModel.cancelOTPChallenge()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
            .background(Color(red: 0.035, green: 0.04, blue: 0.055).ignoresSafeArea())
            .navigationTitle("Двухфакторная защита")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLOUDVAULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Color.blue.opacity(0.9))

            Text("Хранилища")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            Text("Управление подключёнными облачными сервисами")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Общее пространство")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(totalUsed.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text("из \(totalCapacity.formatted(.number.precision(.fractionLength(0)))) GB")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Text("\(providers.count) подключено")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(Color.blue)
                        .frame(
                            width: totalCapacity > 0
                                ? geometry.size.width * min(totalUsed / totalCapacity, 1)
                                : 0
                        )
                }
            }
            .frame(height: 9)

            Text("Использовано \(totalCapacity > 0 ? Int(totalUsed / totalCapacity * 100) : 0)% доступного пространства")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(18)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Подключённые сервисы")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(providers) { provider in
                StorageProviderCardView(provider: provider)
            }
        }
    }

    // MARK: - Add storage

    private var addStorageButton: some View {
        Button {
            showingAddStorage = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))

                Text("Добавить хранилище")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Google Drive sheet

    private var addStorageSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerPicker

                    if viewModel.activeErrorMessage != nil || viewModel.activeSuccessMessage != nil {
                        messagesSection
                    }

                    if viewModel.activeAccount == nil {
                        connectSection
                    } else {
                        providerSection
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.035, green: 0.04, blue: 0.055).ignoresSafeArea())
            .navigationTitle(viewModel.activeAccount == nil ? "Подключение" : viewModel.selectedProvider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        showingAddStorage = false
                    }
                }
            }
            .alert("Новая папка", isPresented: $showingCreateFolder) {
                TextField("Название папки", text: $newFolderName)

                Button("Создать") {
                    let name = newFolderName
                    newFolderName = ""
                    Task {
                        await viewModel.createFolder(named: name)
                    }
                }

                Button("Отмена", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("Папка будет создана в текущей папке Google Drive.")
            }
            .alert(
                "Свойства файла",
                isPresented: Binding(
                    get: { viewModel.activeSelectedFile != nil },
                    set: { if !$0 { viewModel.activeSelectedFile = nil } }
                )
            ) {
                Button("Закрыть", role: .cancel) {
                    viewModel.activeSelectedFile = nil
                }
            } message: {
                if let file = viewModel.activeSelectedFile {
                    Text(metadataText(for: file))
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.content],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await viewModel.upload(fileURL: url)
                        }
                    }
                case .failure(let error):
                    // Ошибку показываем через состояние активного провайдера.
                    Task { @MainActor in
                        viewModel.reportFilePickerError(error)
                    }
                }
            }
            .confirmationDialog(
                "Перенос «\(pendingTransferFile?.name ?? "файл")»",
                isPresented: Binding(
                    get: { pendingTransferFile != nil },
                    set: { if !$0 { pendingTransferFile = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let file = pendingTransferFile {
                    ForEach(transferTargets, id: \.self) { target in
                        Button("Копировать в \(target.name)") {
                            Task {
                                await viewModel.transferItem(
                                    file,
                                    from: viewModel.selectedProvider,
                                    to: target,
                                    move: false
                                )
                            }
                        }
                        Button("Переместить в \(target.name)", role: .destructive) {
                            Task {
                                await viewModel.transferItem(
                                    file,
                                    from: viewModel.selectedProvider,
                                    to: target,
                                    move: true
                                )
                            }
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Файл будет скопирован или перемещён в текущую папку выбранного хранилища.")
            }
            .sheet(item: Binding(
                get: { viewModel.activeAudioStream },
                set: { viewModel.activeAudioStream = $0 }
            )) { active in
                AudioPlayerView(
                    file: active.file,
                    providerName: active.provider.name,
                    stream: active.stream
                )
            }
        }
    }

    // MARK: - Provider picker

    private var providerPicker: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.availableProviders, id: \.self) { kind in
                Button {
                    viewModel.selectedProvider = kind
                } label: {
                    Text(kind.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            viewModel.selectedProvider == kind
                                ? .white
                                : .white.opacity(0.6)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            viewModel.selectedProvider == kind
                                ? kind.tint.opacity(0.85)
                                : Color.white.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var messagesSection: some View {
        VStack(spacing: 8) {
            if let error = viewModel.activeErrorMessage {
                messageRow(text: error, color: .red)
            }

            if let success = viewModel.activeSuccessMessage {
                messageRow(text: success, color: .green)
            }
        }
    }

    // MARK: - Connect

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "cloud.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(viewModel.selectedProvider.tint)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Text("Подключение \(viewModel.selectedProvider.name)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Text("Подключите аккаунт \(viewModel.selectedProvider.name), чтобы загружать резервные копии и работать с файлами облака.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.connect() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.activeIsBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }

                    Text("Подключить \(viewModel.selectedProvider.name)")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.selectedProvider.tint.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.activeIsBusy)
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Аккаунт
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.activeAccount?.displayName ?? viewModel.selectedProvider.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.activeAccount?.email ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Button("Отключить") {
                    Task { await viewModel.signOut() }
                }
                .font(.system(size: 13))
                .foregroundStyle(.red.opacity(0.85))
                .disabled(viewModel.activeIsBusy)
            }
            .padding(14)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Текущая папка и действия
            HStack(spacing: 10) {
                if !viewModel.activeFolderStack.isEmpty {
                    Button {
                        Task { await viewModel.goBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeIsBusy)
                }

                Text(viewModel.activeCurrentFolder?.name ?? "Корневая папка")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await viewModel.refreshFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeIsBusy)

                Button {
                    showingCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeIsBusy)

                Button {
                    showingFilePicker = true
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.blue.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeIsBusy)
            }

            // Прогресс cloud-to-cloud переноса
            if viewModel.isTransferRunning {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.cyan)
                    Text("Перенос: \(viewModel.transferFileName ?? "")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(viewModel.transferProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .padding(12)
                .background(Color.cyan.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Список файлов
            if viewModel.activeIsBusy && viewModel.activeFiles.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if viewModel.activeFiles.isEmpty {
                Text("В этой папке пока нет файлов.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.activeFiles) { file in
                        driveFileRow(file)
                    }
                }
            }
        }
    }

    /// Провайдеры, в которые можно переносить файл (все подключённые,
    /// кроме текущего).
    private var transferTargets: [StorageProviderType] {
        viewModel.connectedProviders.filter {
            $0 != viewModel.selectedProvider
        }
    }

    private func driveFileRow(_ file: CloudFile) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if file.isFolder {
                        await viewModel.openFolder(file)
                    } else {
                        await viewModel.showMetadata(for: file)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    CloudThumbnailView(
                        file: file,
                        provider: viewModel.thumbnailProvider(for: file)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(file.isFolder
                             ? "Папка"
                             : (file.sizeBytes.map { Self.byteFormatter.string(fromByteCount: $0) } ?? "—"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    if file.isFolder {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.activeIsBusy || viewModel.isTransferRunning)

            // Потоковое воспроизведение аудио без скачивания.
            if viewModel.isAudioFile(file) {
                Button {
                    Task { await viewModel.playAudio(file) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.pink)
                        .frame(width: 34, height: 34)
                        .background(Color.pink.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeIsBusy)
            }

            // Cloud-to-cloud перенос: виден, только если подключено
            // больше одного хранилища.
            if !transferTargets.isEmpty {
                Button {
                    pendingTransferFile = file
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 34, height: 34)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.activeIsBusy || viewModel.isTransferRunning)
            }
        }
    }

    private func messageRow(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metadataText(for file: CloudFile) -> String {
        var lines = [
            "Название: \(file.name)",
            "Тип: \(file.isFolder ? "Папка" : file.mimeType)"
        ]

        if let size = file.sizeBytes {
            lines.append(
                "Размер: \(Self.byteFormatter.string(fromByteCount: size))"
            )
        }

        if let modified = file.modifiedAt {
            lines.append(
                "Изменён: \(modified.formatted(date: .abbreviated, time: .shortened))"
            )
        }

        if let duration = file.duration {
            lines.append(
                "Длительность: \(Int(duration / 60)):\(String(format: "%02d", Int(duration) % 60))"
            )
        }

        return lines.joined(separator: "\n")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if providers.isEmpty {
            Text("Подключите облачное хранилище через кнопку «Добавить хранилище».")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
