import SwiftUI

// MARK: - Taskly Logo
//
// A "T" monogram that doubles as a checkmark: a horizontal top bar (the T's crossbar)
// sitting above a bold checkmark whose tall right arm reads as the T's stem. It says
// the brand initial *and* "done" in one mark — drawn as vector so it stays crisp at
// any size and is reused for both the in-app header and the home-screen app icon.

/// The white mark (bar + checkmark) on a transparent background, drawn in a unit square.
struct TasklyMark: View {
    var lineWidthRatio: CGFloat = 0.14

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * lineWidthRatio
            ZStack {
                // Crossbar of the "T"
                Capsule()
                    .frame(width: s * 0.44, height: lw)
                    .position(x: s * 0.5, y: s * 0.29)

                // Centre stem dropping from the crossbar, then kicking up-right into a
                // checkmark tick — reads unmistakably as "T" while signalling "done".
                Path { p in
                    p.move(to: CGPoint(x: s * 0.50, y: s * 0.30))
                    p.addLine(to: CGPoint(x: s * 0.50, y: s * 0.72))
                    p.addLine(to: CGPoint(x: s * 0.72, y: s * 0.50))
                }
                .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The full app logo tile: brand-green rounded square containing the white mark.
/// Use `cornerRatio: 0` (or a Rectangle) when exporting the raw app-icon artwork,
/// since iOS applies the rounded mask itself.
struct TasklyLogo: View {
    var size: CGFloat = 84
    var cornerRatio: CGFloat = 0.26

    var body: some View {
        RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
            .fill(Brand.gradient)              // subtle tonal green, not multi-hue
            .frame(width: size, height: size)
            .overlay(
                TasklyMark()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
            )
            .shadow(color: .brand.opacity(0.35), radius: size * 0.18, y: size * 0.09)
            .accessibilityLabel("Taskly")
    }
}

#Preview {
    VStack(spacing: 24) {
        TasklyLogo(size: 96)
        TasklyMark().foregroundStyle(Color.brand).frame(width: 80, height: 80)
    }
    .padding()
}
