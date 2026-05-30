import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var nickname = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                    Text("Taskly")
                        .font(.largeTitle.bold())
                    Text("Get things done, together")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Form
                VStack(spacing: 16) {
                    if isRegistering {
                        TextField("Nickname", text: $nickname)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isRegistering ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }
                .padding(.horizontal)

                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await authManager.handleAppleLogin(result: result) }
                }
                .frame(height: 50)
                .padding(.horizontal)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Toggle register/login
                Button {
                    isRegistering.toggle()
                    errorMessage = nil
                } label: {
                    Text(isRegistering ? "Already have an account? Sign In" : "New here? Create Account")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }

                Spacer()
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        do {
            if isRegistering {
                try await authManager.registerWithEmail(email: email, password: password, nickname: nickname)
            } else {
                try await authManager.loginWithEmail(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
