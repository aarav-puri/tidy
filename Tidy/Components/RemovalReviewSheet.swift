import SwiftUI

/// The itemized preview shown before any removal. Nothing is touched until the
/// user confirms here; the sheet then reports exactly what happened.
struct RemovalReviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: RemovalRequest

    private enum Stage { case review, working, done(RemovalOutcome) }
    @State private var stage: Stage = .review

    private var mode: RemovalMode { app.effectiveMode(for: request) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch stage {
            case .review, .working:
                itemList
                footnote
            case .done(let outcome):
                resultView(outcome)
            }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 360, maxHeight: 640)
        .interactiveDismissDisabled(isWorking)
        .task {
            // Users may opt out of confirming Trash moves (which are recoverable). Permanent deletion always asks.
            if mode == .moveToTrash, !app.settings.confirmMoveToTrash { start() }
        }
    }

    private func start() {
        guard case .review = stage else { return }
        stage = .working
        Task {
            let outcome = await app.perform(request)
            stage = .done(outcome)
        }
    }

    private var isWorking: Bool { if case .working = stage { true } else { false } }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerSymbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(headerTint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle).font(.headline)
                Text(headerMessage).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerSymbol: String {
        if case .done(let o) = stage { return o.failures.isEmpty ? "checkmark.circle" : "exclamationmark.circle" }
        return mode == .moveToTrash ? "trash" : "exclamationmark.octagon"
    }

    private var headerTint: Color {
        if case .done(let o) = stage { return o.failures.isEmpty ? .green : .orange }
        return mode == .moveToTrash ? .secondary : .red
    }

    private var headerTitle: String {
        let count = Format.count(request.entries.count, singular: "item")
        switch stage {
        case .done(let o):
            return o.failures.isEmpty ? "Done" : "Finished with \(Format.count(o.failures.count, singular: "issue"))"
        default:
            return mode == .moveToTrash ? "Move \(count) to the Trash?" : "Permanently delete \(count)?"
        }
    }

    private var headerMessage: String {
        switch stage {
        case .done(let o):
            let verb = mode == .moveToTrash ? "moved to the Trash" : "deleted"
            return "\(Format.count(o.removed.count, singular: "item")) (\(Format.bytes(o.bytes))) \(verb)."
        default:
            var text = "\(request.title) · \(Format.bytes(request.totalSize))."
            if let note = request.note { text += " " + note }
            return text
        }
    }

    private var itemList: some View {
        List {
            ForEach(request.entries) { entry in
                HStack(spacing: 10) {
                    FileIcon(url: entry.candidate.url, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                        Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        ForEach(entry.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Text(Format.bytes(entry.candidate.size)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(minHeight: 160)
    }

    @ViewBuilder
    private var footnote: some View {
        if mode != .moveToTrash {
            Label("You can't undo this action.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func resultView(_ outcome: RemovalOutcome) -> some View {
        if outcome.failures.isEmpty {
            Spacer()
        } else {
            Text("These items weren't removed:").font(.callout.weight(.medium))
            List(outcome.failures) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    private var buttons: some View {
        HStack {
            if isWorking {
                ProgressView().controlSize(.small)
                Text(mode == .moveToTrash ? "Moving to Trash…" : "Deleting…").foregroundStyle(.secondary)
            }
            Spacer()
            switch stage {
            case .review:
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .moveToTrash ? "Move to Trash" : "Delete Permanently", role: .destructive, action: start)
                .keyboardShortcut(.defaultAction)
                .disabled(request.entries.isEmpty)
            case .working:
                Button("Cancel") {}.disabled(true)
            case .done:
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
