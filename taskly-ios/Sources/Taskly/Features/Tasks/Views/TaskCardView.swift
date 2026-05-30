import SwiftUI

struct TaskCardView: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(task.category.displayName, systemImage: task.category.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                Spacer()
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Text(task.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label(task.address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(task.currency) \(task.budget, specifier: "%.0f")")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
            }

            if let deadline = task.deadline {
                Label(deadline.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let publisher = task.publisher {
                HStack(spacing: 6) {
                    AsyncImage(url: URL(string: publisher.avatar ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(.systemGray5))
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    Text(publisher.nickname).font(.caption).foregroundStyle(.secondary)
                    if publisher.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", publisher.rating)).font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var statusColor: Color {
        switch task.status {
        case .open: return .green
        case .inProgress: return .orange
        case .pendingConfirm: return .blue
        case .completed: return .gray
        case .cancelled: return .red
        }
    }
}
