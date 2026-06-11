import SwiftUI

/// Report / Block bottom sheet (App Store Guideline 1.2).
///
/// Presented as a `.sheet` with regular buttons rather than a `confirmationDialog`
/// so the controls live in the normal view hierarchy — clearer, and reliably
/// driveable in UI tests (action-sheet/popover buttons are not).
struct ModerationSheet: View {
    /// Noun for the thing being acted on, e.g. "user" or "task".
    var subject: String = "user"
    let onReport: () async -> Void
    /// Optional — omit (nil) to hide the Block button, e.g. when viewing your own content.
    var onBlock: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        VStack(spacing: Space.lg) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, Space.sm)

            VStack(spacing: Space.xs) {
                Text("Report or Block").font(.headline)
                Text("Reports are reviewed within 24 hours. Blocking hides this \(subject)'s content from you immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: Space.sm) {
                Button {
                    Task { working = true; await onReport(); dismiss() }
                } label: {
                    Label("Report this \(subject)", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let onBlock {
                    Button(role: .destructive) {
                        Task { working = true; await onBlock(); dismiss() }
                    } label: {
                        Label("Block this \(subject)", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                Button("Cancel") { dismiss() }
                    .padding(.top, Space.xs)
            }
            .padding(.horizontal)
            .disabled(working)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }
}
