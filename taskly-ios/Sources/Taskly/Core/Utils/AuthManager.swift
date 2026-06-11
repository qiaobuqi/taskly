import SwiftUI
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isLoggedIn = false
    @Published var currentUser: User?

    private init() {
        restoreSession()
    }

    // MARK: - Session

    private func restoreSession() {
        guard let token = UserDefaults.standard.string(forKey: "auth_token"),
              !token.isEmpty else { return }
        isLoggedIn = true
        Task { await fetchCurrentUser() }
    }

    func logout() {
        Analytics.shared.track("logout")
        Analytics.shared.flush()
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        isLoggedIn = false
        currentUser = nil
    }

    // MARK: - Apple Login

    /// Handles the result from `SignInWithAppleButton`. Throws on failure so the
    /// view can show an error — a silently-swallowed failure is exactly what made
    /// the button look "unresponsive" to App Review (Guideline 2.1).
    func handleAppleLogin(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                appleLog("authorization succeeded but credential unreadable: \(auth.credential)")
                trackAppleFailure(stage: "credential", error: nil)
                throw APIError.server("Could not read your Apple ID credentials. Please try again.")
            }
            appleLog("authorization OK — user=\(credential.user) tokenLength=\(token.count) email=\(credential.email ?? "nil")")
            do {
                try await loginWithApple(identityToken: token, credential: credential)
                appleLog("backend login OK")
            } catch {
                trackAppleFailure(stage: "backend", error: error)
                throw error
            }
        case .failure(let error):
            // The user cancelling the sheet is not an error we should surface.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                appleLog("cancelled by user")
                Analytics.shared.track("apple_login_cancelled")
                return
            }
            trackAppleFailure(stage: "authorization", error: error)
            throw error
        }
    }

    /// Flushed immediately: if Apple sign-in fails on a device we can't debug
    /// (e.g. App Review's), the stage + error chain still reach our backend.
    private func trackAppleFailure(stage: String, error: Error?) {
        var props: [String: Any] = ["stage": stage]
        if let error {
            let ns = error as NSError
            props["desc"] = error.localizedDescription
            props["domain"] = ns.domain
            props["ns_code"] = ns.code
            if let authError = error as? ASAuthorizationError {
                props["code"] = authError.code.rawValue
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                props["underlying"] = "\(underlying.domain)#\(underlying.code)"
            }
        }
        appleLog("FAILED stage=\(stage)", error: error)
        Analytics.shared.track("apple_login_failed", props)
        Analytics.shared.flush()
    }

    /// Console log for Apple sign-in debugging. Walks the NSUnderlyingErrorKey
    /// chain — the real cause (AKAuthenticationError etc.) hides 1–2 levels deep.
    private func appleLog(_ msg: String, error: Error? = nil) {
        #if DEBUG
        var line = "🍎 [apple-login] \(msg)"
        var next: NSError? = error.map { $0 as NSError }
        var depth = 0
        while let ns = next, depth < 4 {
            line += "\n   ↳ domain=\(ns.domain) code=\(ns.code) — \(ns.localizedDescription)"
            let info = ns.userInfo.filter { $0.key != NSUnderlyingErrorKey }
            if !info.isEmpty { line += "\n     userInfo: \(info)" }
            next = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        print(line)
        #endif
    }

    private func loginWithApple(identityToken: String, credential: ASAuthorizationAppleIDCredential) async throws {
        struct AppleLoginBody: Encodable {
            let identityToken: String
            let email: String?
            let fullName: String?
        }
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        let body = AppleLoginBody(
            identityToken: identityToken,
            email: credential.email,
            fullName: fullName.isEmpty ? nil : fullName
        )

        struct LoginResponse: Codable {
            let token: String
            let user: User
        }
        let response: LoginResponse = try await NetworkManager.shared.requestJSON("/auth/apple", body: body)
        UserDefaults.standard.set(response.token, forKey: "auth_token")
        UserDefaults.standard.set(response.user.id, forKey: "user_id")
        currentUser = response.user
        isLoggedIn = true
        Analytics.shared.track("login", ["method": "apple"])
    }

    // MARK: - Email Login

    func loginWithEmail(email: String, password: String) async throws {
        struct EmailLoginBody: Encodable {
            let email: String
            let password: String
        }
        struct LoginResponse: Codable {
            let token: String
            let user: User
        }
        let response: LoginResponse = try await NetworkManager.shared.requestJSON(
            "/auth/login",
            body: EmailLoginBody(email: email, password: password)
        )
        UserDefaults.standard.set(response.token, forKey: "auth_token")
        UserDefaults.standard.set(response.user.id, forKey: "user_id")
        currentUser = response.user
        isLoggedIn = true
        Analytics.shared.track("login", ["method": "email"])
    }

    /// Permanently delete the current account (App Store 5.1.1(v)). Logs out on success.
    func deleteAccount() async throws {
        struct MessageResponse: Codable { let message: String? }
        let _: MessageResponse = try await NetworkManager.shared.request("/users/me", method: .delete)
        Analytics.shared.track("account_deleted")
        logout()
    }

    /// Request a 6-digit email verification code for registration.
    func sendCode(email: String) async throws {
        struct CodeBody: Encodable { let email: String }
        struct MessageResponse: Codable { let message: String? }
        let _: MessageResponse = try await NetworkManager.shared.requestJSON(
            "/auth/send-code", body: CodeBody(email: email)
        )
    }

    func registerWithEmail(email: String, password: String, nickname: String, code: String) async throws {
        struct RegisterBody: Encodable {
            let email: String
            let password: String
            let nickname: String
            let code: String
        }
        struct LoginResponse: Codable {
            let token: String
            let user: User
        }
        let response: LoginResponse = try await NetworkManager.shared.requestJSON(
            "/auth/register",
            body: RegisterBody(email: email, password: password, nickname: nickname, code: code)
        )
        UserDefaults.standard.set(response.token, forKey: "auth_token")
        UserDefaults.standard.set(response.user.id, forKey: "user_id")
        currentUser = response.user
        isLoggedIn = true
        Analytics.shared.track("sign_up", ["method": "email"])
    }

    private func fetchCurrentUser() async {
        do {
            let user: User = try await NetworkManager.shared.request("/users/me")
            currentUser = user
        } catch APIError.unauthorized {
            // The server rejected the token — the session is genuinely dead.
            logout()
        } catch {
            // Transient failure (offline, timeout at cold launch): keep the cached
            // session; the profile loads on the next successful request.
        }
    }
}
