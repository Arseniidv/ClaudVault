import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct AuthPasswordField: View {

    // MARK: - Properties

    let title: String
    let placeholder: String

    @Binding var password: String

    #if canImport(UIKit)
    var textContentType: UITextContentType? = .password
    #endif

    @State private var isPasswordVisible = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary.opacity(0.55))
                    .frame(width: 22)

                Group {
                    if isPasswordVisible {
                        TextField(placeholder, text: $password)
                    } else {
                        SecureField(placeholder, text: $password)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                #endif

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isPasswordVisible
                        ? "Скрыть пароль"
                        : "Показать пароль"
                )
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
    }
}
