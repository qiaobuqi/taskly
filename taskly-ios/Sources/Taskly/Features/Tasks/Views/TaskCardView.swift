import SwiftUI
import Kingfisher

struct TaskCardView: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // Category tile + name, status chip trailing
            HStack(spacing: Space.sm) {
                CategoryIcon(category: task.category)
                Text(task.category.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusChip(status: task.status)
            }

            Text(task.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Meta: location + optional deadline
            VStack(alignment: .leading, spacing: Space.xs) {
                metaRow(icon: "mappin.and.ellipse", text: task.address)
                if let deadline = task.deadline {
                    metaRow(icon: "clock", text: deadline.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Divider()

            // Poster + budget
            HStack(spacing: Space.sm) {
                if let publisher = task.publisher {
                    avatar(publisher)
                    Text(publisher.nickname)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if publisher.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(Color.brand)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", publisher.rating)).font(.caption)
                    }
                    .padding(.leading, Space.xs)
                }
                Spacer()
                BudgetPill(currency: task.currency, amount: task.budget)
            }
        }
        .cardSurface()
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func avatar(_ user: User) -> some View {
        KFImage(URL(string: user.avatar ?? ""))
            .placeholder {
                Circle().fill(Color(.systemGray5))
                    .overlay(Image(systemName: "person.fill").font(.caption2).foregroundStyle(.gray))
            }
            .resizable().scaledToFill()
            .frame(width: 24, height: 24)
            .clipShape(Circle())
    }
}

/// Rounded, brand-tinted tile holding the category's SF Symbol — gives each card a
/// small splash of color and a quick visual category cue (TaskRabbit-style).
struct CategoryIcon: View {
    let category: TaskCategory
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.brand.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: category.icon)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Color.brand)
            )
    }
}
