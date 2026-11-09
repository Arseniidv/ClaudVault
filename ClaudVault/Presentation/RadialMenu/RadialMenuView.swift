#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Radial Menu — плавающее меню быстрых действий над файлами.
/// Содержимое зависит от `coordinator.mode`: кольцо действий,
/// выбор облака, информация о файлах или fallback-подсказка.
/// Панель также является drop-таргетом: перетаскивание файлов
/// на меню открывает его с этим выделением.
struct RadialMenuView: View {

    let coordinator: RadialMenuCoordinator

    private let panelWidth: CGFloat = 460
    private let panelHeight: CGFloat = 460
    private let center = CGPoint(x: 230, y: 230)
    private let ringRadius: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.surface)
                .overlay(
                    Circle().stroke(AppColors.border, lineWidth: 1)
                )

            switch coordinator.mode {
            case .actions:
                actionsContent
            case .providers:
                providersContent
            case .information:
                informationContent
            case .fallback:
                fallbackContent
            }

            if coordinator.isWorking {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColors.accent)
                    if let status = coordinator.statusMessage {
                        Text(status)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 180)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
            }

            // Кнопка добавления файлов к выделению —
            // в режимах кольца действий и fallback.
            if coordinator.mode == .actions
                || coordinator.mode == .fallback {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            coordinator.addFiles()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(Circle())
        .onExitCommand { coordinator.dismiss() }
        .onKeyPress(.escape) {
            coordinator.dismiss()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Actions ring

    private var actionsContent: some View {
        ZStack {
            ForEach(
                Array(coordinator.actionDescriptors.enumerated()),
                id: \.element.id
            ) { index, descriptor in
                actionItem(descriptor, index: index)
            }

            centerView
        }
    }

    private func actionItem(
        _ descriptor: FileActionDescriptor,
        index: Int
    ) -> some View {
        let count = max(coordinator.actionDescriptors.count, 1)
        // Равномерно по кругу, начиная сверху, по часовой.
        let degrees = -90.0 + Double(index) * (360.0 / Double(count))
        let radians = degrees * .pi / 180
        let position = CGPoint(
            x: center.x + CGFloat(cos(radians)) * ringRadius,
            y: center.y + CGFloat(sin(radians)) * ringRadius
        )

        return Button {
            coordinator.selectAction(descriptor.kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: descriptor.kind.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(
                                descriptor.isEnabled
                                    ? AppColors.accentMuted
                                    : Color.primary.opacity(0.05)
                            )
                    )
                    .overlay(
                        Circle().stroke(
                            descriptor.isEnabled
                                ? AppColors.accent.opacity(0.5)
                                : AppColors.border,
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(
                        descriptor.isEnabled
                            ? AppColors.accent
                            : AppColors.textMuted
                    )
                Text(descriptor.kind.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        descriptor.isEnabled
                            ? AppColors.textSecondary
                            : AppColors.textMuted
                    )
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!descriptor.isEnabled)
        .position(position)
        .onHover { hovering in
            coordinator.hoveredAction = hovering
                ? descriptor.kind
                : (coordinator.hoveredAction == descriptor.kind
                    ? nil
                    : coordinator.hoveredAction)
        }
    }

    /// Центральный элемент: счётчик файлов, источник выделения
    /// и описание наведённого/статусного действия.
    private var centerView: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(AppColors.accentMuted)
                .frame(width: 92, height: 92)
                .overlay(
                    VStack(spacing: 2) {
                        Text("\(coordinator.selection?.files.count ?? 0)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(fileWord)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                )
                .overlay(
                    Circle().stroke(AppColors.border, lineWidth: 1)
                )

            if let hovered = coordinator.hoveredAction,
               let descriptor = coordinator.actionDescriptors.first(
                   where: { $0.kind == hovered }
               ) {
                Text(descriptor.kind.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(width: 130)
            } else if let status = coordinator.statusMessage {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(width: 150)
            } else {
                Text(coordinator.selection?.source.displayName ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .position(center)
    }

    private var fileWord: String {
        let count = coordinator.selection?.files.count ?? 0
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1, mod100 != 11 { return "файл" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) {
            return "файла"
        }
        return "файлов"
    }

    // MARK: - Provider picker

    private var providersContent: some View {
        VStack(spacing: 12) {
            headerRow(
                title: pendingTitle,
                backAction: { coordinator.backToActions() }
            )

            if ProviderAvailabilityService.shared.connectedProviders.isEmpty {
                Spacer()
                Image(systemName: "icloud.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColors.textMuted)
                Text("Нет подключённых облаков")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Подключите хранилище во вкладке «Хранилища».")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(
                            ProviderAvailabilityService.shared
                                .connectedProviders
                        ) { provider in
                            providerRow(provider)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var pendingTitle: String {
        guard let kind = coordinator.pendingProviderAction else {
            return "Выберите облако"
        }
        return "\(kind.title): облако"
    }

    private func providerRow(_ provider: StorageProviderType) -> some View {
        Button {
            coordinator.selectProvider(provider)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(provider.tint))
                Text(provider.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Information

    private var informationContent: some View {
        VStack(spacing: 0) {
            headerRow(
                title: "Информация",
                backAction: { coordinator.backToActions() }
            )

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(coordinator.information) { info in
                        infoCard(info)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func infoCard(_ info: FileInspectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Text(info.path)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                if let size = info.sizeText {
                    label("Размер", size)
                }
                if let modified = info.modifiedText {
                    label("Изменён", modified)
                }
            }

            if info.backupVersionsCount > 0,
               let provider = info.backupProviderName {
                HStack(spacing: 12) {
                    label("Копия", provider)
                    label("Версий", "\(info.backupVersionsCount)")
                    if let uploaded = info.lastUploadText {
                        label("Загружен", uploaded)
                    }
                }
            } else {
                Text("Резервная копия отсутствует")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textMuted)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.textMuted)

            Text(coordinator.statusMessage ?? "")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 300)

            Button {
                Task { await coordinator.useClipboardFallback() }
            } label: {
                Label("Взять файлы из буфера обмена",
                      systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)

            Text("Esc — закрыть")
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textMuted)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Shared chrome

    private func headerRow(
        title: String,
        backAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: backAction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button {
                coordinator.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            await MainActor.run {
                coordinator.present(urls: urls, source: .dragAndDrop)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard let item = try? await provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier
        ) else { return nil }
        if let url = item as? URL { return url }
        if let nsurl = item as? NSURL { return nsurl as URL }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        return nil
    }
}
#endif
