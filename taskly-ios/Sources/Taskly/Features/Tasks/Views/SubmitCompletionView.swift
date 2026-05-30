import SwiftUI
import PhotosUI

struct SubmitCompletionView: View {
    let task: TaskItem
    let onSuccess: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var note = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            if didSubmit {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64)).foregroundStyle(.green)
                    Text("Submitted!").font(.title2.bold())
                    Text("Waiting for the task owner to confirm completion. Payment will be released automatically in 48 hours if no response.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .padding(.horizontal)
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                Form {
                    Section("Completion Photos") {
                        PhotosPicker(selection: $selectedItems, maxSelectionCount: 6,
                                     matching: .images) {
                            Label("Add Photos", systemImage: "camera")
                        }
                        .onChange(of: selectedItems) { _, items in
                            Task { await loadImages(from: items) }
                        }
                        if !selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(selectedImages.indices, id: \.self) { i in
                                        Image(uiImage: selectedImages[i])
                                            .resizable().scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    Section("Notes (optional)") {
                        TextField("Describe what was done...", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    if let error = errorMessage {
                        Section { Text(error).foregroundStyle(.red).font(.caption) }
                    }
                }
                .navigationTitle("Submit Completion")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(isLoading || selectedImages.isEmpty)
                    }
                }
                .overlay { if isLoading { ProgressView() } }
            }
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        selectedImages = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImages.append(image)
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Upload images first
            var imageUrls: [String] = []
            for image in selectedImages {
                if let url = try? await uploadImage(image) { imageUrls.append(url) }
            }
            struct CompletionBody: Encodable {
                let note: String
                let completionImages: [String]
            }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/tasks/\(task.id)/complete",
                body: CompletionBody(note: note, completionImages: imageUrls)
            )
            didSubmit = true
            await onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadImage(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.badURL)
        }
        struct UploadResponse: Codable { let url: String }
        let response: UploadResponse = try await NetworkManager.shared.uploadImage(data, path: "/upload/image")
        return response.url
    }
}
