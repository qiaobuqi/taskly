import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var nickname = ""
    @State private var code = ""
    @State private var cooldown = 0
    @State private var sendingCode = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAppleError = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                HStack {
                    Spacer()
                    Button("Skip") { dismiss() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                header
                form
                divider
                appleButton
                toggle
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        // Dismiss the login sheet automatically once any auth path succeeds.
        .onChange(of: authManager.isLoggedIn) { _, loggedIn in
            if loggedIn { dismiss() }
        }
        // Apple sign-in failures must be LOUD: a silent failure reads as "the
        // button is unresponsive" (App Review rejected exactly this, twice).
        .alert("Sign in with Apple Failed", isPresented: $showAppleError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((errorMessage ?? "Something went wrong.")
                 + "\n\nYou can also sign in with your email and password.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: Space.md) {
            TasklyLogo(size: 84)

            VStack(spacing: Space.xs) {
                Text("Taskly").font(.largeTitle.bold())
                Text(isRegistering ? "Create your account" : "Get things done, together")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Space.lg)
        .padding(.bottom, Space.sm)
    }

    private var form: some View {
        VStack(spacing: Space.md) {
            if isRegistering {
                IconField(icon: "person", placeholder: "Nickname", text: $nickname)
            }
            IconField(icon: "envelope", placeholder: "Email", text: $email, keyboard: .emailAddress)
            IconField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)

            if isRegistering {
                HStack(spacing: Space.sm) {
                    IconField(icon: "number", placeholder: "Verification code", text: $code, keyboard: .numberPad)
                    Button {
                        Task { await sendCode() }
                    } label: {
                        Group {
                            if sendingCode { ProgressView().tint(.white) }
                            else { Text(cooldown > 0 ? "\(cooldown)s" : "Send code") }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 100, height: 52)
                        .foregroundStyle(.white)
                        .background(canSendCode ? Color.brand : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .disabled(!canSendCode)
                }
            }

            if let error = errorMessage {
                HStack(spacing: Space.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await submit() }
            } label: {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(isRegistering ? "Create Account" : "Sign In")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading)
            .padding(.top, Space.xs)
        }
    }

    private var divider: some View {
        HStack(spacing: Space.md) {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task {
                isLoading = true
                do {
                    try await authManager.handleAppleLogin(result: result)
                } catch {
                    errorMessage = error.localizedDescription
                    showAppleError = true
                }
                isLoading = false
            }
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            if isLoading {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.black.opacity(0.5))
                ProgressView().tint(.white)
            }
        }
        .disabled(isLoading)
    }

    private var toggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRegistering.toggle()
                errorMessage = nil
            }
        } label: {
            Text(isRegistering ? "Already have an account? Sign In" : "New here? Create Account")
                .font(.subheadline)
                .foregroundStyle(Color.brand)
        }
    }

    private var canSendCode: Bool {
        cooldown == 0 && !sendingCode && email.contains("@")
    }

    private func sendCode() async {
        guard canSendCode else { return }
        sendingCode = true
        errorMessage = nil
        do {
            try await authManager.sendCode(email: email)
            // Start the 60s resend cooldown.
            cooldown = 60
            Task {
                while cooldown > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    cooldown -= 1
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        sendingCode = false
    }

    private func submit() async {
        // Friendly client-side validation — submitting empty fields otherwise
        // surfaces the backend's raw validator error (and a 400 in the logs).
        guard email.contains("@"), !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }
        if isRegistering {
            guard !nickname.isEmpty else {
                errorMessage = "Please choose a nickname."
                return
            }
            guard !code.isEmpty else {
                errorMessage = "Please enter the verification code sent to your email."
                return
            }
        }
        isLoading = true
        errorMessage = nil
        do {
            if isRegistering {
                try await authManager.registerWithEmail(email: email, password: password, nickname: nickname, code: code)
            } else {
                try await authManager.loginWithEmail(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
