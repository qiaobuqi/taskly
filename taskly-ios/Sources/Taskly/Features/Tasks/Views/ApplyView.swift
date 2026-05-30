import SwiftUI

struct ApplyView: View {
    let task: TaskItem
    @Environment(\.dismiss) var dismiss
    @State private var message = ""
    @State private var proposedPrice: Double
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didApply = false

    init(task: TaskItem) {
        self.task = task
        _proposedPrice = State(initialValue: task.budget)
    }

    var body: some View {
        NavigationStack {
            if didApply {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("Application Sent!")
                        .font(.title2.bold())
                    Text("The task owner will review your application and get back to you.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                Form {
                    Section("Your Offer") {
                        HStack {
                            Text("$")
                            TextField("Price", value: $proposedPrice, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                    Section("Message to Owner") {
                        TextField("Introduce yourself and explain why you're the best fit...",
                                  text: $message, axis: .vertical)
                            .lineLimit(4...8)
                    }
                    if let error = errorMessage {
                        Section {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                    }
                }
                .navigationTitle("Apply for Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task { await apply() }
                        }
                        .fontWeight(.semibold)
                        .disabled(isLoading || message.isEmpty)
                    }
                }
            }
        }
    }

    private func apply() async {
        isLoading = true
        errorMessage = nil
        do {
            struct ApplyBody: Encodable {
                let taskId: Int
                let message: String
                let proposedPrice: Double
            }
            struct ApplyResponse: Codable { let id: Int }
            let _: ApplyResponse = try await NetworkManager.shared.requestJSON(
                "/tasks/\(task.id)/apply",
                body: ApplyBody(taskId: task.id, message: message, proposedPrice: proposedPrice)
            )
            didApply = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
