import SwiftUI

/// Shown in place of personal screens (Profile, Messages) when browsing as a guest.
/// Tapping "Sign In" opens the login sheet via the shared router.
struct SignInPromptView: View {
    let message: String
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: Space.lg) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(Color.brand)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { router.showLogin = true } label: { Text("Sign In") }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 240)
            Spacer()
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
