import SwiftUI
import Kingfisher

struct MessagesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var vm = MessagesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.isLoggedIn {
                    SignInPromptView(message: "Sign in to see your messages")
                } else if vm.conversations.isEmpty && vm.isLoading {
                    // Centered spinner on first load — never a blank list flash.
                    ProgressView()
                } else if vm.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Message a poster from any task to start chatting")
                    )
                } else {
                    List(vm.conversations) { conv in
                        NavigationLink {
                            ChatView(otherUser: conv.otherUser, taskId: nil)
                        } label: {
                            ConversationRowView(conversation: conv)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.loadConversations() }
                }
            }
            .navigationTitle("Messages")
            // Keyed on login state: skips the request entirely for guests (no
            // spinner over the sign-in prompt) and reloads right after login.
            .task(id: authManager.isLoggedIn) {
                guard authManager.isLoggedIn else { return }
                await vm.loadConversations()
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation

    // Show "📷 Photo" for image-only messages so no row ever has a blank preview line.
    private var lastMessagePreview: String {
        guard let msg = conversation.lastMessage else { return "" }
        if msg.content.isEmpty, let url = msg.imageUrl, !url.isEmpty {
            return "📷 Photo"
        }
        return msg.content
    }

    var body: some View {
        HStack(spacing: 12) {
            // KFImage like the rest of the app (ProfileView etc.) — AsyncImage
            // rides URLSession.shared and caches nothing.
            KFImage(URL(string: conversation.otherUser.avatar ?? ""))
                .placeholder {
                    Circle().fill(Color(.systemGray5))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.gray))
                }
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.otherUser.nickname).font(.headline)
                Text(lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let msg = conversation.lastMessage {
                Text(msg.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false

    func loadConversations() async {
        isLoading = true
        do {
            conversations = try await NetworkManager.shared.request("/messages/conversations")
        } catch {
            print("Failed to load conversations: \(error)")
        }
        isLoading = false
    }
}
