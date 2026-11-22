import SwiftUI

/// Display text that reads like polished glass: a luminous fill that fades
/// toward the bottom, a bright specular edge along the top, and a soft lift.
/// Always fully legible; the effect is in the fill, never over the glyphs.
struct GlassText: View {
    let text: String
    var size: CGFloat = 44
    var weight: Font.Weight = .semibold
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, size: CGFloat = 44, weight: Font.Weight = .semibold) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    private var font: Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }

    var body: some View {
        let base = Text(text).font(font)
        base
            .foregroundStyle(fill)
            .overlay {
                // Specular highlight on the upper part of each glyph.
                base
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.9 : 0.75), .white.opacity(0)],
                                                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.3 : 0.08), radius: size * 0.12, y: size * 0.05)
            .accessibilityLabel(text)
    }

    private var fill: LinearGradient {
        if scheme == .dark {
            return LinearGradient(colors: [.white, .white.opacity(0.74)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.78)],
                              startPoint: .top, endPoint: .bottom)
    }
}
