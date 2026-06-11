import SwiftUI
import PhotosUI

struct PostTaskView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = PostTaskViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task Info"),
                        footer: Text(vm.title.isEmpty ? "Title is required" : "")) {
                    TextField("Title (required)", text: $vm.title)
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

                Section(header: Text("Photos"),
                        footer: Text("Add up to 6 photos to help Taskers understand the job.")) {
                    PhotosPicker(selection: $vm.selectedItems, maxSelectionCount: 6,
                                 matching: .images) {
                        Label("Add a Photo", systemImage: "photo.badge.plus")
                    }
                    .onChange(of: vm.selectedItems) { _, items in
                        Task { await vm.loadImages(from: items) }
                    }
                    if !vm.selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(vm.selectedImages.indices, id: \.self) { i in
                                    Image(uiImage: vm.selectedImages[i])
                                        .resizable().scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section(header: Text("Location"),
                        footer: Text(vm.address.isEmpty ? "Address is required to post" : "")) {
                    TextField("Address (required)", text: $vm.address)
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
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var selectedImages: [UIImage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        selectedImages = loaded
    }

    private func uploadImage(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.badURL)
        }
        struct UploadResponse: Codable { let url: String }
        let response: UploadResponse = try await NetworkManager.shared.uploadImage(data, path: "/upload/image")
        return response.url
    }

    func post() async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            // Upload any attached photos first, then post with their URLs. A failed
            // upload aborts the post (surfacing the error below) — silently posting
            // without the photos the user attached would be worse.
            var imageUrls: [String] = []
            for image in selectedImages {
                imageUrls.append(try await uploadImage(image))
            }
            struct PostBody: Encodable {
                let title: String
                let description: String
                let category: String
                let budget: Double
                let currency: String
                let address: String
                let deadline: Date?
                let images: [String]
            }
            let _: TaskItem = try await NetworkManager.shared.requestJSON("/tasks", body: PostBody(
                title: title,
                description: description,
                category: category.rawValue,
                budget: budget,
                currency: "USD",
                address: address,
                deadline: hasDeadline ? deadline : nil,
                images: imageUrls
            ))
            Analytics.shared.track("post_task_submit", ["category": category.rawValue, "budget": budget])
            NotificationCenter.default.post(name: .tasksDidChange, object: nil)
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
