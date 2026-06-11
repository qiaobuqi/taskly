import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        // Three clean destinations. "Post" is no longer a tab — it's a floating
        // action button on the Tasks screen (see TaskBoardView), which is the more
        // mainstream pattern for a create action (Airtasker / Gmail style).
        TabView(selection: $router.selectedTab) {
            TaskBoardView()
                .tabItem { Label("Tasks", systemImage: "list.bullet.clipboard") }
                .tag(0)

            MessagesView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                .tag(1)

            ProfileView()
                .tabItem { Label("Me", systemImage: "person.circle") }
                .tag(2)
        }
        .onChange(of: router.selectedTab) { _, tab in
            Analytics.shared.screen(["tasks", "messages", "profile"][tab])
        }
        .sheet(isPresented: $router.showPostTask) { PostTaskView() }
        .sheet(isPresented: $router.showPostService) { PostServiceView() }
        .tint(.brand)   // green selected-tab + system controls, consistent with brand
    }
}
