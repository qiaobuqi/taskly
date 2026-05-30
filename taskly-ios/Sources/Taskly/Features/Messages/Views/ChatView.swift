import SwiftUI

struct ChatView: View {
    let otherUser: User
    let taskId: Int?
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var vm: ChatViewModel
    @State private var inputText = ""

    init(otherUser: User, taskId: Int?) {
        self.otherUser = otherUser
        self.taskId = taskId
        _vm = StateObject(wrappedValue: ChatViewModel(otherUserId: otherUser.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromMe: message.senderId == authManager.currentUser?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let text = inputText
                    inputText = ""
                    Task { await vm.sendMessage(text, taskId: taskId) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.background)
        }
        .navigationTitle(otherUser.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadMessages() }
    }
}

struct MessageBubble: View {
    let message: Message
    let isFromMe: Bool

    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isFromMe ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isFromMe ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
            if !isFromMe { Spacer() }
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false

    private let otherUserId: Int

    init(otherUserId: Int) {
        self.otherUserId = otherUserId
    }

    func loadMessages() async {
        isLoading = true
        do {
            let msgs: [Message] = try await NetworkManager.shared.request(
                "/messages/\(otherUserId)"
            )
            messages = msgs
        } catch {
            print("Failed to load messages: \(error)")
        }
        isLoading = false
    }

    func sendMessage(_ content: String, taskId: Int?) async {
        do {
            struct SendBody: Encodable {
                let receiverId: Int
                let content: String
                let taskId: Int?
            }
            let msg: Message = try await NetworkManager.shared.requestJSON(
                "/messages",
                body: SendBody(receiverId: otherUserId, content: content, taskId: taskId)
            )
            messages.append(msg)
        } catch {
            print("Failed to send message: \(error)")
        }
    }
}
