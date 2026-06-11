import SwiftUI

/// First-launch privacy/terms consent. Shown once before the user can use the app;
/// acceptance is remembered. Links to the hosted Privacy Policy and Terms so the user
/// can review them before agreeing — standard practice and expected by reviewers.
private struct LegalItem: Identifiable { let id = UUID(); let title: String; let url: URL }

struct PrivacyConsentView: View {
    var onAgree: () -> Void
    @State private var legal: LegalItem?

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()
            TasklyLogo(size: 84)
            Text("Welcome to Taskly")
                .font(.title.bold())
            Text("Taskly helps you get local tasks done together. Before you start, please review how we handle your data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Space.sm) {
                Button { legal = LegalItem(title: "Privacy Policy", url: Legal.privacyURL) } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Button { legal = LegalItem(title: "Terms of Service", url: Legal.termsURL) } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                }
            }
            .font(.subheadline.weight(.medium))
            .tint(.brand)
            .padding(.top, Space.sm)

            Spacer()

            Text("By tapping “Agree & Continue”, you agree to our Privacy Policy and Terms of Service.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button { onAgree() } label: { Text("Agree & Continue") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xl)
        .background(Color.appBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
        .sheet(item: $legal) { item in
            LegalView(title: item.title, url: item.url)
        }
    }
}
