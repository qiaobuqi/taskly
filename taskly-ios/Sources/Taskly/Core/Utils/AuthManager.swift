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
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        isLoggedIn = false
        currentUser = nil
    }

    // MARK: - Apple Login

    func handleAppleLogin(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            await loginWithApple(identityToken: token, credential: credential)
        case .failure:
            break
        }
    }

    private func loginWithApple(identityToken: String, credential: ASAuthorizationAppleIDCredential) async {
        do {
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
        } catch {
            print("Apple login failed: \(error)")
        }
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
    }

    func registerWithEmail(email: String, password: String, nickname: String) async throws {
        struct RegisterBody: Encodable {
            let email: String
            let password: String
            let nickname: String
        }
        struct LoginResponse: Codable {
            let token: String
            let user: User
        }
        let response: LoginResponse = try await NetworkManager.shared.requestJSON(
            "/auth/register",
            body: RegisterBody(email: email, password: password, nickname: nickname)
        )
        UserDefaults.standard.set(response.token, forKey: "auth_token")
        UserDefaults.standard.set(response.user.id, forKey: "user_id")
        currentUser = response.user
        isLoggedIn = true
    }

    private func fetchCurrentUser() async {
        do {
            let user: User = try await NetworkManager.shared.request("/users/me")
            currentUser = user
        } catch {
            logout()
        }
    }
}
