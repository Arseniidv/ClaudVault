import SwiftUI

/// Экран переноса подключений облаков между устройствами (QR Guard).
///
/// - «Новое устройство»: показывает QR-код и ждёт пакет.
/// - «Доверенное устройство»: сканирует QR и отправляет токены.
struct DeviceTransferView: View {

    @State private var viewModel: DeviceTransferViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: DeviceTransferViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    switch viewModel.mode {
                    case .none:
                        modePicker
                    case .generator:
                        generatorContent
                    case .scanner:
                        scannerContent
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.035, green: 0.04, blue: 0.055).ignoresSafeArea())
            .navigationTitle("Перенос подключений")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.consumePendingDeepLink()
            }
            .onDisappear {
                viewModel.reset()
            }
            .sheet(isPresented: $viewModel.isScannerPresented) {
                scannerSheet
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEVICE TRANSFER")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Color.blue.opacity(0.9))

            Text("Перенос подключений")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Text("Безопасно перенесите Google Drive, Dropbox и OneDrive на другое устройство с помощью QR-кода. Данные шифруются end-to-end.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        VStack(spacing: 14) {
            modeCard(
                icon: "qrcode.viewfinder",
                title: "Я на новом устройстве",
                subtitle: "Показать QR-код и получить подключения"
            ) {
                viewModel.chooseGenerator()
            }

            modeCard(
                icon: "qrcode",
                title: "Я на доверенном устройстве",
                subtitle: "Сканировать QR-код и отправить подключения"
            ) {
                viewModel.chooseScanner()
            }
        }
    }

    private func modeCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(Color.cyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generator

    @ViewBuilder
    private var generatorContent: some View {
        VStack(spacing: 20) {
            // QR и спиннер актуальны только пока идёт создание сессии,
            // генерация кода и ожидание сканирования — после получения
            // пакета или ошибки код мёртв.
            if viewModel.phase == .working
                || viewModel.phase == .generatingQRCode
                || viewModel.phase == .awaitingScan {
                if let qrImage = viewModel.qrImage {
                    Image(decorative: qrImage, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(20)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    ProgressView()
                        .tint(.cyan)
                        .frame(height: 200)
                }
            }

            statusRow

            if case .awaitingScan = viewModel.phase {
                Button("Отменить") {
                    viewModel.cancelGenerator()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            }

            if case .awaitingRestore = viewModel.phase {
                VStack(spacing: 10) {
                    ForEach(viewModel.incomingProviders, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.cyan)
                    }

                    HStack(spacing: 12) {
                        Button("Отклонить") {
                            viewModel.cancelRestore()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button("Применить") {
                            viewModel.confirmRestore()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerContent: some View {
        VStack(spacing: 20) {
            if let pending = viewModel.pendingTransfer {
                pendingTransferCard(pending)
            } else {
                #if os(iOS)
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black)
                    .frame(height: 280)
                    .overlay(
                        Text("Камера недоступна")
                            .foregroundStyle(.white.opacity(0.5))
                    )
                #else
                manualEntrySection
                #endif
            }

            statusRow
        }
    }

    /// Карточка подтверждения: показывает, куда и что будет отправлено,
    /// и требует явного нажатия перед биометрией и передачей токенов.
    private func pendingTransferCard(
        _ pending: DeviceTransferViewModel.PendingTransfer
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Входящий запрос на перенос", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                if let email = pending.ownerEmail, !email.isEmpty {
                    detailRow(title: "Аккаунт", value: email)
                }
                if let createdAt = pending.createdAt {
                    detailRow(
                        title: "Создана",
                        value: createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                detailRow(title: "Сессия", value: pending.sessionID)
            }

            Text("Будут отправлены токены всех подключённых облаков (Google Drive, Dropbox, OneDrive). Убедитесь, что запрос создан на вашем новом устройстве.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 12) {
                Button("Отклонить") {
                    viewModel.cancelPendingTransfer()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Отправить подключения") {
                    viewModel.approvePendingTransfer()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Шит с камерой сканера (iOS).
    private var scannerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(iOS)
                QRCodeScannerView { code in
                    viewModel.handleScannedValue(code)
                }
                .ignoresSafeArea(edges: .bottom)
                #endif

                VStack(spacing: 12) {
                    Text("Наведите камеру на QR-код с нового устройства")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    manualEntrySection
                }
                .padding(20)
                .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Сканирование QR")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        viewModel.isScannerPresented = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Ручной ввод ссылки/ID сессии — работает на всех платформах.
    private var manualEntrySection: some View {
        VStack(spacing: 10) {
            TextField(
                "claudvault://verify?session=… или ID сессии",
                text: $viewModel.manualSessionInput
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

            Button("Проверить сессию") {
                viewModel.submitManualSession()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(
                viewModel.manualSessionInput
                    .trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
    }

    // MARK: - Status

    private var isFailedPhase: Bool {
        if case .failed = viewModel.phase { return true }
        return viewModel.phase == .expired
    }

    @ViewBuilder
    private var statusRow: some View {
        switch viewModel.phase {
        case .idle:
            EmptyView()
        case .working, .generatingQRCode:
            HStack(spacing: 10) {
                ProgressView().tint(.cyan)
                Text(viewModel.statusMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .awaitingScan, .awaitingRestore, .completed, .expired, .failed:
            VStack(spacing: 10) {
                Text(viewModel.statusMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(isFailedPhase ? .red : .white.opacity(0.75))
                    .multilineTextAlignment(.center)

                if case .completed = viewModel.phase {
                    ForEach(viewModel.restoredProviders, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }

                if isFailedPhase, viewModel.mode == .scanner {
                    Button("Сканировать снова") {
                        viewModel.reset()
                        viewModel.chooseScanner()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.cyan)
                }

                if isFailedPhase, viewModel.mode == .generator {
                    Button("Создать QR заново") {
                        viewModel.chooseGenerator()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.cyan)
                }
            }
        }
    }
}
