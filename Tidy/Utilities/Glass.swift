import SwiftUI

extension View {
    /// Applies the native Liquid Glass material on macOS 26 and later, and the
    /// closest standard material on earlier releases. Use for floating control
    /// layers only, never for content.
    @ViewBuilder
    func controlGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.bar, in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        }
    }

    /// Standard prominent push button. Uses the system glass prominent style where
    /// the platform provides it for floating controls.
    @ViewBuilder
    func floatingProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// Liquid Glass on any shape, optionally tinted and reacting to the pointer.
    /// `clear` asks for the more transparent variant; it is used only in Dark Mode,
    /// where the content behind is dark enough to keep text legible.
    /// Falls back to a translucent material before macOS 26.
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive, clear: clear))
    }

    /// Lets one glass shape morph into another with the same id as state changes.
    @ViewBuilder
    func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self.matchedGeometryEffect(id: id, in: namespace)
        }
    }

    /// Groups nearby glass shapes so they render and blend together.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// The regular glass push button, or bordered before macOS 26.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Wraps an animation so it is dropped when Reduce Motion is on.
struct MotionAware {
    static func animation(_ animation: Animation = .snappy(duration: 0.25), reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let clear: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let base = clear && scheme == .dark ? Glass.clear : Glass.regular
            content.glassEffect(base.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(tint.map { AnyShapeStyle($0.opacity(0.18)) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.stroke(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}
