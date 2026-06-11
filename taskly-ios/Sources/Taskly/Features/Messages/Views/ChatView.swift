import SwiftUI

struct ChatView: View {
    let otherUser: User
    let taskId: Int?
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ChatViewModel
    @State private var inputText = ""
    @State private var showModeration = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showModeration = true } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showModeration) {
            ModerationSheet(
                subject: "user",
                onReport: { await vm.report() },
                onBlock: {
                    await vm.blockUser()
                    dismiss()
                }
            )
        }
        .task { await vm.loadMessages() }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
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
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false

    private let otherUserId: Int

    init(otherUserId: Int) {
        self.otherUserId = otherUserId
    }

    func loadMessages() async {
        isLoading = true
        do {
            let msgs: [ChatMessage] = try await NetworkManager.shared.request(
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
            let msg: ChatMessage = try await NetworkManager.shared.requestJSON(
                "/messages",
                body: SendBody(receiverId: otherUserId, content: content, taskId: taskId)
            )
            messages.append(msg)
        } catch {
            print("Failed to send message: \(error)")
        }
    }

    /// Report this user to the moderation queue (reviewed within 24h).
    func report() async {
        do {
            struct ReportBody: Encodable { let targetType, reason: String; let targetId: Int }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/reports",
                body: ReportBody(targetType: "user", reason: "inappropriate", targetId: otherUserId)
            )
        } catch { print("Report failed: \(error)") }
    }

    /// Block this user: notifies the developer and removes their content from the
    /// feed immediately (App Store Guideline 1.2).
    func blockUser() async {
        do {
            struct BlockBody: Encodable { let blockedId: Int; let reason: String }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/blocks",
                body: BlockBody(blockedId: otherUserId, reason: "blocked from chat")
            )
            NotificationCenter.default.post(name: .tasksDidChange, object: nil)
        } catch { print("Block failed: \(error)") }
    }
}
