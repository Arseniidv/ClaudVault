import SwiftUI

struct AddBackupButton: View {

    var action: () -> Void
    /// Если задано — кнопка превращается в меню выбора источника
    /// (сканирование документа / выбор файла). На macOS не передаётся.
    var scanAction: (() -> Void)? = nil

    init(
        action: @escaping () -> Void,
        scanAction: (() -> Void)? = nil
    ) {
        self.action = action
        self.scanAction = scanAction
    }

    private var buttonLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(
                LinearGradient(
                    colors: [
                        Color.blue,
                        Color.cyan
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .shadow(
                color: Color.blue.opacity(0.35),
                radius: 12,
                x: 0,
                y: 5
            )
    }

    var body: some View {
        if let scanAction {
            Menu {
                #if os(iOS)
                Button {
                    scanAction()
                } label: {
                    Label("Отсканировать документ", systemImage: "doc.viewfinder")
                }
                #endif

                Button {
                    action()
                } label: {
                    Label("Выбрать файл", systemImage: "folder")
                }
            } label: {
                buttonLabel
            }
            .accessibilityLabel("Создать резервную копию")
        } else {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Создать резервную копию")
        }
    }
}
