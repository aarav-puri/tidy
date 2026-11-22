import SwiftUI

/// A segmented capacity bar in the style of System Settings > General > Storage.
struct StorageBar: View {
    struct Segment: Identifiable, Hashable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
        var isEstimate = false
    }

    let segments: [Segment]
    let total: Int64
    var height: CGFloat = 22

    @State private var hovered: String?

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let visible = segments.filter { $0.bytes > 0 }
            let available = proxy.size.width - spacing * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(visible) { segment in
                    let width = max(3, available * CGFloat(Double(segment.bytes) / Double(max(total, 1))))
                    Rectangle()
                        .fill(segment.isEstimate ? AnyShapeStyle(segment.color.opacity(0.55)) : AnyShapeStyle(segment.color))
                        .frame(width: width)
                        .opacity(hovered == nil || hovered == segment.id ? 1 : 0.45)
                        .onHover { hovered = $0 ? segment.id : (hovered == segment.id ? nil : hovered) }
                        .help("\(segment.title): \(Format.bytes(segment.bytes))\(segment.isEstimate ? " (estimated)" : "")")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color.secondary.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage usage")
        .accessibilityValue(segments.map { "\($0.title) \(Format.bytes($0.bytes))" }.joined(separator: ", "))
    }
}

struct StorageLegend: View {
    let segments: [StorageBar.Segment]

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(segments.filter { $0.bytes > 0 }) { segment in
                HStack(spacing: 5) {
                    Circle().fill(segment.color.opacity(segment.isEstimate ? 0.55 : 1)).frame(width: 8, height: 8)
                    Text(segment.title).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension StorageCategory.Kind {
    /// Restrained system colors, matching the palette macOS uses for storage categories.
    var color: Color {
        switch self {
        case .applications: .red
        case .documents: .orange
        case .photos: .yellow
        case .downloads: .green
        case .developer: .blue
        case .library: .purple
        case .systemAndOther: .gray
        case .available: .clear
        }
    }
}

/// A thin proportional bar used inside list rows.
struct SizeBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(tint.gradient).frame(width: max(2, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
