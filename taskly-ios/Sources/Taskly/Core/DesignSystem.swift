import SwiftUI

// MARK: - Design System
//
// One source of truth for Taskly's visual language. The goal is to lift the app
// out of "default SwiftUI" and give it a consistent, premium feel comparable to
// marketplace apps like Airtasker / Airbnb: a confident accent, generous spacing,
// soft elevation, and reusable button/card styles so every screen feels related.
//
// Deploys to iOS 17+, so nothing here requires iOS 26 Liquid Glass APIs.

// MARK: Color

extension Color {
    /// Primary brand accent — a confident emerald "Trades Green" (think TaskRabbit:
    /// green = done / go / trustworthy). Deliberately a single solid hue, not the
    /// indigo→violet gradient that screams "AI-generated app".
    static let brand = Color(red: 0.118, green: 0.620, blue: 0.353)        // #1E9E5A
    /// Darker tonal green for the far end of subtle same-hue surfaces (header only).
    static let brandSecondary = Color(red: 0.082, green: 0.514, blue: 0.247) // #15833F

    /// Warm off-white app background (#F7F8F6) in light mode, true system bg in dark.
    /// The warmth reads more "designed" than the default cool gray.
    static let appBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 0.969, green: 0.973, blue: 0.965, alpha: 1)
    })
    /// Raised card surface — adaptive white / dark.
    static let cardSurface = Color(.secondarySystemGroupedBackground)
}

enum Brand {
    /// Subtle *tonal* green gradient (same hue, light→dark) for hero surfaces like the
    /// profile header. Tonal, not multi-hue — keeps depth without the AI-rainbow look.
    static let gradient = LinearGradient(
        colors: [.brand, .brandSecondary],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Consistent status color used by badges and cards across the app.
    /// `open` is teal (not green) so it stays distinct from the green brand color.
    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .open: return Color(red: 0.05, green: 0.6, blue: 0.65)  // teal, distinct from brand
        case .inProgress: return .orange
        case .pendingConfirm: return .blue
        case .completed: return .gray
        case .cancelled: return .red
        case .disputed: return .purple
        }
    }
}

// MARK: Spacing / Radius

/// 8-pt spacing scale. Using named steps keeps rhythm consistent between screens.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
}

// MARK: Card surface

extension View {
    /// Raised content surface: padded, rounded, soft shadow. The building block of
    /// every card so elevation and corner radius stay identical everywhere.
    func cardSurface(padding: CGFloat = Space.lg, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(padding)
            .background(Color.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: Button styles

/// Filled, solid-color button for the single primary action on a screen.
/// Solid (not gradient) on purpose — reads as an intentional brand choice.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .brand
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(enabled ? tint : Color.gray.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .shadow(color: tint.opacity(enabled ? 0.28 : 0), radius: 10, y: 5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Tinted, low-emphasis button for secondary actions sitting next to a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.brand)
            .background(Color.brand.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Reusable components

/// Text field with a leading SF Symbol inside a filled, rounded container.
/// Carries an accessibility label (the placeholder), fixing the "nameless field"
/// VoiceOver issue the bare TextField had.
struct IconField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.body)
        }
        .padding(.horizontal, Space.lg)
        .frame(height: 52)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityLabel(placeholder)
    }
}

/// Bold trailing price pill — the "this is what you earn" focal point on task cards.
struct BudgetPill: View {
    let currency: String
    let amount: Double

    var body: some View {
        Text("\(currency) \(amount, specifier: "%.0f")")
            .font(.subheadline.bold())
            .foregroundStyle(Color.brand)
            .padding(.horizontal, Space.md)
            .padding(.vertical, 6)
            .background(Color.brand.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// Small colored status capsule, consistent with `Brand.statusColor`.
struct StatusChip: View {
    let status: TaskStatus
    var body: some View {
        Text(status.displayName)
            .font(.caption.bold())
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 4)
            .background(Brand.statusColor(status).opacity(0.15))
            .foregroundStyle(Brand.statusColor(status))
            .clipShape(Capsule())
    }
}
