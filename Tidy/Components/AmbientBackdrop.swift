import SwiftUI

/// The window's backdrop: a quiet neutral surface lit by one soft wash of the
/// app icon's blue, so Liquid Glass has something to catch without competing
/// with content. Static, so it costs nothing while the app sits open.
struct AmbientBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    /// The blue of the app icon.
    static let iconBlue = Color(red: 0.0, green: 0.42, blue: 0.96)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let reach = max(size.width, size.height)
            ZStack {
                base
                // Main light, from above the center.
                RadialGradient(colors: [Self.iconBlue.opacity(isDark ? 0.34 : 0.16), .clear],
                               center: UnitPoint(x: 0.58, y: -0.15),
                               startRadius: 0, endRadius: reach * 0.75)
                // A faint bounce of the same blue at the lower left.
                RadialGradient(colors: [Self.iconBlue.opacity(isDark ? 0.12 : 0.06), .clear],
                               center: UnitPoint(x: 0.05, y: 1.1),
                               startRadius: 0, endRadius: reach * 0.55)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var isDark: Bool { scheme == .dark }

    private var base: Color {
        isDark ? Color(red: 0.071, green: 0.078, blue: 0.094) : Color(red: 0.957, green: 0.961, blue: 0.969)
    }
}
