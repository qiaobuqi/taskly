import SwiftUI

struct MessagesView: View {
    @StateObject private var vm = MessagesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.conversations.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Apply for a task to start chatting")
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
            .task { await vm.loadConversations() }
            .overlay {
                if vm.isLoading && vm.conversations.isEmpty {
                    ProgressView()
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: conversation.otherUser.avatar ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color(.systemGray5))
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.gray))
            }
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
                Text(conversation.lastMessage?.content ?? "")
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
            let users: [User] = try await NetworkManager.shared.request("/messages/conversations")
            conversations = users.map { user in
                Conversation(id: user.id, otherUser: user, lastMessage: nil, unreadCount: 0)
            }
        } catch {
            print("Failed to load conversations: \(error)")
        }
        isLoading = false
    }
}
