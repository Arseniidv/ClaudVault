import SwiftUI
#if os(iOS)
import MessageUI
#endif
#if os(macOS)
import AppKit
#endif

/// Кросс-платформенная обёртка для отправки письма.
/// iOS: системный `MFMailComposeViewController` (MessageUI).
/// macOS: `mailto:` через системную «Почту» (MessageUI на macOS отсутствует).
struct MailComposer: View {
    let recipient: String
    let subject: String
    let messageBody: String

    var body: some View {
        #if os(iOS)
        MailComposerRepresentable(
            recipient: recipient,
            subject: subject,
            messageBody: messageBody
        )
        #else
        MacMailComposerFallback(
            recipient: recipient,
            subject: subject,
            messageBody: messageBody
        )
        #endif
    }
}

// MARK: - iOS

#if os(iOS)

private struct MailComposerRepresentable: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let messageBody: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(
        context: Context
    ) -> MFMailComposeViewController {
        let mailController = MFMailComposeViewController()
        mailController.mailComposeDelegate = context.coordinator
        mailController.setToRecipients([recipient])
        mailController.setSubject(subject)
        mailController.setMessageBody(messageBody, isHTML: false)
        return mailController
    }

    func updateUIViewController(
        _ controller: MFMailComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}

#endif

// MARK: - macOS

#if os(macOS)

private struct MacMailComposerFallback: View {
    let recipient: String
    let subject: String
    let messageBody: String

    @Environment(\.dismiss) private var dismiss
    @State private var didOpen = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Письмо будет открыто в приложении «Почта»")
                .font(.headline)

            Text("\(recipient)\n\(subject)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Открыть в Почте") {
                    openMailApp()
                }
                .buttonStyle(.borderedProminent)

                Button("Отмена") {
                    dismiss()
                }
            }
        }
        .padding(32)
        .frame(minWidth: 380)
        .onAppear {
            guard !didOpen else { return }
            didOpen = true
            openMailApp()
        }
    }

    private func openMailApp() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        var items = [URLQueryItem(name: "subject", value: subject)]
        if !messageBody.isEmpty {
            items.append(URLQueryItem(name: "body", value: messageBody))
        }
        components.queryItems = items

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}

#endif
