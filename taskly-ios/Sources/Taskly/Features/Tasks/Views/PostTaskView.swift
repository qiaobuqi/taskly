import SwiftUI
import PhotosUI

struct PostTaskView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PostTaskViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Info") {
                    TextField("Title", text: $vm.title)
                    TextField("Description", text: $vm.description, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $vm.category) {
                        ForEach(TaskCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Budget & Time") {
                    HStack {
                        Text("$")
                        TextField("Budget", value: $vm.budget, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("Set deadline", isOn: $vm.hasDeadline)
                    if vm.hasDeadline {
                        DatePicker("Deadline", selection: $vm.deadline, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Location") {
                    TextField("Address", text: $vm.address)
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Post Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            if await vm.post() { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(vm.isLoading || vm.title.isEmpty || vm.address.isEmpty)
                }
            }
            .overlay {
                if vm.isLoading { ProgressView() }
            }
        }
    }
}

@MainActor
final class PostTaskViewModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var category: TaskCategory = .other
    @Published var budget: Double = 50
    @Published var address = ""
    @Published var hasDeadline = false
    @Published var deadline = Date().addingTimeInterval(86400)
    @Published var isLoading = false
    @Published var errorMessage: String?

    func post() async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            struct PostBody: Encodable {
                let title: String
                let description: String
                let category: String
                let budget: Double
                let currency: String
                let address: String
                let deadline: Date?
            }
            let _: TaskItem = try await NetworkManager.shared.requestJSON("/tasks", body: PostBody(
                title: title,
                description: description,
                category: category.rawValue,
                budget: budget,
                currency: "USD",
                address: address,
                deadline: hasDeadline ? deadline : nil
            ))
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
