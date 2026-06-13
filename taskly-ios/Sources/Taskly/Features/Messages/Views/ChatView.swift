import SwiftUI
import PhotosUI
import Kingfisher

struct ChatView: View {
    let otherUser: User
    let taskId: Int?
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ChatViewModel
    @State private var inputText = ""
    @State private var showModeration = false
    @State private var photoItem: PhotosPickerItem?

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
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if vm.isSendingImage {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(vm.isSendingImage)
                .accessibilityLabel("Send a Photo")
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    // Reset the binding only AFTER the send: nilling it mid-dismissal
                    // can make the picker re-assign the item and double-send.
                    Task {
                        await vm.sendImage(from: item, taskId: taskId)
                        photoItem = nil
                    }
                }

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
                    Task {
                        let ok = await vm.sendMessage(text, taskId: taskId)
                        // Failed? Put the text back so it isn't lost (unless the
                        // user already started typing something new).
                        if !ok && inputText.isEmpty { inputText = text }
                    }
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
        .alert("Message Not Sent", isPresented: Binding(
            get: { vm.sendError != nil },
            set: { if !$0 { vm.sendError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.sendError ?? "Please check your connection and try again.")
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
            if let url = message.imageUrl, !url.isEmpty {
                KFImage(URL(string: url))
                    .placeholder {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.systemGray5))
                            .overlay(ProgressView())
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Photo message")
            } else {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isFromMe ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
            }
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

    @Published var isSendingImage = false
    @Published var sendError: String?

    private struct SendBody: Encodable {
        let receiverId: Int
        let content: String
        let imageUrl: String?
        let taskId: Int?
    }

    /// POST with one automatic retry (transient drops are common on mobile).
    /// Returns false and sets `sendError` on final failure so the caller can
    /// restore the user's input instead of losing it silently.
    private func deliver(_ body: SendBody) async -> Bool {
        for attempt in 1...2 {
            do {
                let msg: ChatMessage = try await NetworkManager.shared.requestJSON("/messages", body: body)
                messages.append(msg)
                return true
            } catch {
                if attempt == 2 { sendError = error.localizedDescription }
            }
        }
        return false
    }

    /// Pick → compress → upload → send as an image message.
    func sendImage(from item: PhotosPickerItem, taskId: Int?) async {
        guard !isSendingImage else { return }   // dedup: one in-flight send max
        isSendingImage = true
        defer { isSendingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.8) else {
                sendError = "Could not read that photo. Please try another one."
                return
            }
            struct UploadResponse: Codable { let url: String }
            let uploaded: UploadResponse = try await NetworkManager.shared.uploadImage(jpeg, path: "/upload/image")
            _ = await deliver(SendBody(receiverId: otherUserId, content: "", imageUrl: uploaded.url, taskId: taskId))
        } catch {
            sendError = error.localizedDescription
        }
    }

    @discardableResult
    func sendMessage(_ content: String, taskId: Int?) async -> Bool {
        await deliver(SendBody(receiverId: otherUserId, content: content, imageUrl: nil, taskId: taskId))
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
