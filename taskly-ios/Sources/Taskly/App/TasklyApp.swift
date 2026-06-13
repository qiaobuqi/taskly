import SwiftUI

@main
struct TasklyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Cold-launch open — first signal for DAU.
        Analytics.shared.track("app_open", ["logged_in": AuthManager.shared.isLoggedIn])
        Analytics.shared.startSession(cold: true)
        // Flush immediately instead of waiting for the 5s debounce: the first
        // network request at launch triggers the cellular-data permission prompt
        // (China-market devices) right away and warms up DNS/TLS for the API.
        Analytics.shared.flush()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(router)
        }
        .onChange(of: scenePhase) { old, new in
            switch new {
            case .active where old == .background:
                Analytics.shared.startSession(cold: false)   // return-to-foreground
            case .background:
                Analytics.shared.appDidEnterBackground()
            default:
                break
            }
        }
    }
}
