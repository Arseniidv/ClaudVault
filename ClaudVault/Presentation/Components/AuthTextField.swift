import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct AuthTextField: View {

    // MARK: - Properties

    let title: String
    let placeholder: String
    let systemImage: String

    @Binding var text: String

    #if canImport(UIKit)
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    #endif

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 12) {

                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary.opacity(0.55))
                    .frame(width: 22)

                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textPrimary)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    #endif
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
