import SwiftUI

struct PostServiceView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PostServiceViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Info") {
                    TextField("Title (e.g. AC Installation Expert)", text: $vm.title)
                    TextField("Description", text: $vm.description, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $vm.category) {
                        ForEach(TaskCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("Min $")
                        TextField("50", value: $vm.minPrice, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Max $")
                        TextField("200", value: $vm.maxPrice, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Skills & Area") {
                    TextField("Skills (comma separated)", text: $vm.skillsText)
                        .autocorrectionDisabled()
                    TextField("Service area (e.g. Sydney CBD)", text: $vm.serviceArea)
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Offer a Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { if await vm.post() { dismiss() } }
                    }
                    .fontWeight(.semibold)
                    .disabled(vm.isLoading || vm.title.isEmpty || vm.serviceArea.isEmpty)
                }
            }
            .overlay { if vm.isLoading { ProgressView() } }
        }
    }
}

@MainActor
final class PostServiceViewModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var category: TaskCategory = .other
    @Published var minPrice: Double = 50
    @Published var maxPrice: Double = 200
    @Published var skillsText = ""
    @Published var serviceArea = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func post() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // `post_service_submit` only fires on success — mark the attempt so the
        // service-post funnel shows attempt → submit and surfaces silent failures.
        Analytics.shared.track("post_service_attempt", ["category": category.rawValue])
        do {
            struct PostBody: Encodable {
                let title, description, category, serviceArea, currency: String
                let minPrice, maxPrice: Double
                let skillTags: [String]
            }
            let tags = skillsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let _: ServiceCard = try await NetworkManager.shared.requestJSON("/services", body: PostBody(
                title: title, description: description, category: category.rawValue,
                serviceArea: serviceArea, currency: "USD",
                minPrice: minPrice, maxPrice: maxPrice, skillTags: tags
            ))
            Analytics.shared.track("post_service_submit", ["category": category.rawValue])
            NotificationCenter.default.post(name: .tasksDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            Analytics.shared.track("post_service_failed", ["category": category.rawValue, "desc": error.localizedDescription])
            Analytics.shared.flush()
            return false
        }
    }
}
