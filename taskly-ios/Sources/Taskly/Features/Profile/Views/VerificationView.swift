import SwiftUI
import PhotosUI

struct VerificationView: View {
    @Environment(\.dismiss) var dismiss
    @State private var realName = ""
    @State private var documentType = "passport"
    @State private var frontItem: PhotosPickerItem?
    @State private var frontImage: UIImage?
    @State private var backItem: PhotosPickerItem?
    @State private var backImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @State private var verificationStatus: VerificationStatus = .none

    let documentTypes = [("passport", "Passport"), ("id_card", "National ID"), ("driving_license", "Driver's License")]

    var body: some View {
        NavigationStack {
            if didSubmit || verificationStatus == .pending {
                pendingView
            } else if verificationStatus == .approved {
                approvedView
            } else {
                formView
            }
        }
    }

    private var pendingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill").font(.system(size: 64)).foregroundStyle(.orange)
            Text("Under Review").font(.title2.bold())
            Text("We'll verify your identity within 24 hours. You'll be notified once approved.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Verification")
    }

    private var approvedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.blue)
            Text("Identity Verified").font(.title2.bold())
            Text("Your identity has been verified. You can now accept tasks.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Verification")
    }

    private var formView: some View {
        Form {
            Section("Personal Info") {
                TextField("Full name (as on document)", text: $realName)
                Picker("Document Type", selection: $documentType) {
                    ForEach(documentTypes, id: \.0) { type in
                        Text(type.1).tag(type.0)
                    }
                }
            }

            Section("Document Front") {
                PhotosPicker(selection: $frontItem, matching: .images) {
                    if let image = frontImage {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Label("Upload Front Side", systemImage: "camera")
                    }
                }
                .onChange(of: frontItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            frontImage = UIImage(data: data)
                        }
                    }
                }
            }

            Section("Document Back (if applicable)") {
                PhotosPicker(selection: $backItem, matching: .images) {
                    if let image = backImage {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Label("Upload Back Side", systemImage: "camera")
                    }
                }
                .onChange(of: backItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            backImage = UIImage(data: data)
                        }
                    }
                }
            }

            Section {
                Text("Your documents are encrypted and only used for identity verification. They won't be shared with other users.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Verify Identity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") { Task { await submit() } }
                    .fontWeight(.semibold)
                    .disabled(isLoading || realName.isEmpty || frontImage == nil)
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        do {
            let v: Verification = try await NetworkManager.shared.request("/users/me/verification")
            verificationStatus = v.status
        } catch {}
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var frontUrl = ""
            var backUrl: String? = nil
            if let img = frontImage,
               let data = img.jpegData(compressionQuality: 0.85) {
                struct UploadResp: Codable { let url: String }
                let r: UploadResp = try await NetworkManager.shared.uploadImage(data, path: "/upload/image")
                frontUrl = r.url
            }
            if let img = backImage,
               let data = img.jpegData(compressionQuality: 0.85) {
                struct UploadResp: Codable { let url: String }
                let r: UploadResp = try await NetworkManager.shared.uploadImage(data, path: "/upload/image")
                backUrl = r.url
            }
            struct VerifyBody: Encodable {
                let realName, documentType, frontImageUrl: String
                let backImageUrl: String?
            }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/users/me/verification",
                body: VerifyBody(realName: realName, documentType: documentType,
                                 frontImageUrl: frontUrl, backImageUrl: backUrl)
            )
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
