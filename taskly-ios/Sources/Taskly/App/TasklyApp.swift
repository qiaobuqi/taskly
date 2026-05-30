import SwiftUI

@main
struct TasklyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(router)
        }
    }
}
