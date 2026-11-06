import SwiftUI

/// Поле ввода 6-значного OTP-кода. Автоматически вызывает `onSubmit`
/// при вводе шестой цифры.
struct OTPCodeField: View {
    var onSubmit: (String) -> Void

    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("000000", text: $code)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .focused($isFocused)
            .onChange(of: code) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(6))
                if digits != code {
                    code = digits
                }
                if code.count == 6 {
                    onSubmit(code)
                }
            }
            .onAppear { isFocused = true }
    }
}
