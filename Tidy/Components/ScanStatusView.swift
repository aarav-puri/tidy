import SwiftUI

/// Inline scan progress, matching the restrained progress presentation of Apple's utilities.
struct ScanStatusView: View {
    let title: String
    let detail: String
    let progress: Double?
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let progress {
                        Text(Format.percent(progress)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if let progress {
                    ProgressView(value: progress).progressViewStyle(.linear)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(detail.isEmpty ? " " : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let onCancel {
                Button("Stop", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Large empty or introductory state for a screen, built on ContentUnavailableView.
struct IntroView<Actions: View>: View {
    let title: String
    let symbol: String
    let message: String
    @ViewBuilder var actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 84, height: 84)
                .glass(in: Circle(), tint: Color.accentColor.opacity(0.18), clear: true)
                .shadow(color: Color.accentColor.opacity(glow ? 0.45 : 0.2), radius: glow ? 26 : 14)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                GlassText(title, size: 28)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 10) { actions }
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(36)
        .glass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), clear: true)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
