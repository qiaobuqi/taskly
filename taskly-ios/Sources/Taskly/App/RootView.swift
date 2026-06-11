import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var router: AppRouter
    @AppStorage("privacy_accepted") private var privacyAccepted = false

    var body: some View {
        ZStack {
            // Guests can browse the app; login is requested on demand (posting,
            // applying, messages, profile) via router.showLogin.
            MainTabView()

            if !privacyAccepted {
                PrivacyConsentView {
                    withAnimation { privacyAccepted = true }
                    Analytics.shared.track("privacy_accepted")
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .sheet(isPresented: $router.showLogin) {
            LoginView()
        }
    }
}
