import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: Int = 0
    @Published var showLogin = false
    @Published var showPostTask = false
    @Published var showPostService = false

    private init() {}
}
