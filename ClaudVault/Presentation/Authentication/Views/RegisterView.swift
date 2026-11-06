import SwiftUI

struct RegisterView: View {
    let authViewModel: AuthViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 16) {
                    AuthTextField(
                        title: "Имя",
                        placeholder: "Как вас зовут",
                        systemImage: "person",
                        text: $name
                    )

                    AuthTextField(
                        title: "Email",
                        placeholder: "example@mail.com",
                        systemImage: "envelope",
                        text: $email
                    )

                    AuthPasswordField(
                        title: "Пароль",
                        placeholder: "Минимум 6 символов",
                        password: $password
                    )

                    AuthPasswordField(
                        title: "Повторите пароль",
                        placeholder: "Введите пароль ещё раз",
                        password: $confirmPassword
                    )
                }

                if let error = authViewModel.errorMessage {
                    messageRow(text: error, color: .red)
                }

                signUpButton
            }
            .padding(24)
        }
        .background(
            Color(red: 0.035, green: 0.04, blue: 0.055)
                .ignoresSafeArea()
        )
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authViewModel.clearMessages()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Color.blue.opacity(0.9))
                .padding(.top, 24)

            Text("Создание аккаунта")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Регистрация через Firebase Authentication")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private var signUpButton: some View {
        Button {
            Task {
                await authViewModel.signUp(
                    name: name,
                    email: email,
                    password: password,
                    confirmPassword: confirmPassword
                )
            }
        } label: {
            HStack(spacing: 10) {
                if authViewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Зарегистрироваться")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
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
}
