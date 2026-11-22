import SwiftUI

extension RiskLevel {
    var tint: Color {
        switch self {
        case .recommended: .green
        case .review: .orange
        case .protected: .secondary
        }
    }
}

struct RiskLabel: View {
    let risk: RiskLevel
    var compact = false

    var body: some View {
        Label {
            if !compact { Text(risk.title) }
        } icon: {
            Image(systemName: risk.symbol).foregroundStyle(risk.tint)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(risk.summary)
        .accessibilityLabel(risk.title)
    }
}

/// Shown at the top of screens whose results are limited without Full Disk Access.
struct FullDiskAccessBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("Some locations weren't scanned").font(.callout.weight(.medium))
                .help(message)
            Spacer()
            Button("Open Privacy Settings") { Permissions.openFullDiskAccessSettings() }
                .glassButtonStyle()
                .controlSize(.small)
        }
        .padding(10)
        .glass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
