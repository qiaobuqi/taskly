import SwiftUI
import Kingfisher

struct ServiceCardView: View {
    let service: ServiceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(service.category.displayName, systemImage: service.category.icon)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                Spacer()
                if !service.skillTags.isEmpty {
                    Text(service.skillTags.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(service.title)
                .font(.headline)
                .lineLimit(2)

            Text(service.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label(service.serviceArea, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(service.currency) \(service.minPrice, specifier: "%.0f") – \(service.maxPrice, specifier: "%.0f")")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }

            if let provider = service.provider {
                HStack(spacing: 6) {
                    KFImage(URL(string: provider.avatar ?? ""))
                        .placeholder { Circle().fill(Color(.systemGray5)) }
                        .resizable().scaledToFill()
                        .frame(width: 20, height: 20).clipShape(Circle())
                    Text(provider.nickname).font(.caption).foregroundStyle(.secondary)
                    if provider.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", provider.rating)).font(.caption)
                        Text("(\(provider.completedCount))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

struct ServiceCardDetailView: View {
    let service: ServiceCard
    @EnvironmentObject var authManager: AuthManager
    @State private var showChat = false

    var isOwner: Bool { authManager.currentUser?.id == service.providerId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(service.category.displayName, systemImage: service.category.icon)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(service.title).font(.title2.bold())
                    Text("\(service.currency) \(service.minPrice, specifier: "%.0f") – \(service.maxPrice, specifier: "%.0f")")
                        .font(.title.bold()).foregroundStyle(.blue)
                }
                .padding()

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(icon: "doc.text", label: "Description", value: service.description)
                    DetailRow(icon: "mappin.and.ellipse", label: "Service Area", value: service.serviceArea)
                    if !service.skillTags.isEmpty {
                        DetailRow(icon: "tag", label: "Skills", value: service.skillTags.joined(separator: ", "))
                    }
                }
                .padding()

                if let provider = service.provider {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Provider").font(.headline)
                        UserRowView(user: provider)
                    }
                    .padding()
                }

                Spacer(minLength: 100)
            }
        }
        .navigationTitle(service.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !isOwner {
                Button {
                    showChat = true
                } label: {
                    Label("Contact Provider", systemImage: "bubble.left")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(.blue).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showChat) {
            if let provider = service.provider {
                ChatView(otherUser: provider, taskId: nil)
            }
        }
    }
}
