import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var router: AppRouter
    @State private var showPostSheet = false
    @State private var postMode: PostMode = .task

    enum PostMode { case task, service }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            TaskBoardView()
                .tabItem { Label("Tasks", systemImage: "list.bullet.clipboard") }
                .tag(0)

            Color.clear
                .tabItem { Label("Post", systemImage: "plus.circle.fill") }
                .tag(1)

            MessagesView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Me", systemImage: "person.circle") }
                .tag(3)
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab == 1 {
                showPostSheet = true
                router.selectedTab = 0
            }
        }
        .confirmationDialog("What do you want to post?", isPresented: $showPostSheet) {
            Button("Post a Task") {
                postMode = .task
                router.showPostTask = true
            }
            Button("Offer a Service") {
                postMode = .service
                router.showPostService = true
            }
        }
        .sheet(isPresented: $router.showPostTask) { PostTaskView() }
        .sheet(isPresented: $router.showPostService) { PostServiceView() }
    }
}
