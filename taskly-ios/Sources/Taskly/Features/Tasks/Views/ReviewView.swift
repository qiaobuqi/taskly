import SwiftUI

struct ReviewView: View {
    let task: TaskItem
    let reviewee: User
    let onSuccess: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var rating = 5
    @State private var comment = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            if didSubmit {
                VStack(spacing: 20) {
                    Image(systemName: "star.fill").font(.system(size: 64)).foregroundStyle(.yellow)
                    Text("Review Submitted!").font(.title2.bold())
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                Form {
                    Section("Rating for \(reviewee.nickname)") {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(.yellow)
                                    .onTapGesture { rating = star }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Comment") {
                        TextField("Share your experience...", text: $comment, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    if let error = errorMessage {
                        Section { Text(error).foregroundStyle(.red).font(.caption) }
                    }
                }
                .navigationTitle("Leave a Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(isLoading || comment.isEmpty)
                    }
                }
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            struct ReviewBody: Encodable {
                let taskId, revieweeId, rating: Int
                let comment: String
            }
            let _: Review = try await NetworkManager.shared.requestJSON(
                "/reviews",
                body: ReviewBody(taskId: task.id, revieweeId: reviewee.id, rating: rating, comment: comment)
            )
            didSubmit = true
            await onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
