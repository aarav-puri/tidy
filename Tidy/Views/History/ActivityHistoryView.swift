import SwiftUI

struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.title)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(entry.bytes)).monospacedDigit()
                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        if entry.kind == .emptyTrash { return entry.detail ?? "Emptied the Trash" }
        let verb = entry.mode == .moveToTrash ? "moved to the Trash" : "deleted"
        var text = "\(Format.count(entry.items.count, singular: "item")) \(verb)"
        if entry.failureCount > 0 { text += ", \(entry.failureCount) skipped" }
        return text
    }
}

struct ActivityHistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: HistoryEntry.ID?
    @State private var confirmClear = false
    @State private var restoreMessage: String?

    var body: some View {
        Group {
            if app.history.entries.isEmpty {
                IntroView(title: "No Activity Yet", symbol: "clock.arrow.circlepath",
                          message: "Items you remove appear here.") {}
            } else {
                HSplitView {
                    List(selection: $selection) {
                        Section {
                            LabeledContent("Total Reclaimed", value: Format.bytes(app.history.totalReclaimed))
                                .selectionDisabled()
                        }
                        ForEach(groupedEntries, id: \.0) { title, entries in
                            Section(title) {
                                ForEach(entries) { entry in
                                    HistoryRow(entry: entry).tag(entry.id)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 320, idealWidth: 380)

                    detail
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Activity History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History", systemImage: "trash.slash") { confirmClear = true }
                    .disabled(app.history.entries.isEmpty)
                    .help("Clear History")
            }
        }
        .confirmationDialog("Clear History?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { app.history.clear() }
        }
        .alert("Put Back", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var groupedEntries: [(String, [HistoryEntry])] {
        let calendar = Calendar.current
        var groups: [(String, [HistoryEntry])] = []
        for entry in app.history.entries {
            let title: String
            if calendar.isDateInToday(entry.date) { title = "Today" }
            else if calendar.isDateInYesterday(entry.date) { title = "Yesterday" }
            else { title = entry.date.formatted(.dateTime.month(.wide).year()) }
            if groups.last?.0 == title { groups[groups.count - 1].1.append(entry) } else { groups.append((title, [entry])) }
        }
        return groups
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = app.history.entries.first(where: { $0.id == selection }) {
            if entry.items.isEmpty {
                ContentUnavailableView(entry.kind.title, systemImage: entry.kind.symbol,
                                       description: Text(entry.detail ?? ""))
            } else {
                List(entry.items) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(filePath: item.originalPath).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text((item.originalPath as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        if let trashed = item.trashedPath, FileSystem.exists(URL(filePath: trashed)) {
                            Button("Put Back") { restore(item) }
                                .controlSize(.small)
                                .help("Put Back")
                        } else {
                            Text(item.trashedPath == nil ? "Deleted" : "Not in Trash")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        } else {
            ContentUnavailableView("Select an Activity", systemImage: "clock",
                                   description: Text("Select an activity to see its items."))
        }
    }

    private func restore(_ item: RemovedItem) {
        do {
            try FileRemover.restore(item)
            restoreMessage = "“\(URL(filePath: item.originalPath).lastPathComponent)” was put back."
        } catch {
            restoreMessage = error.localizedDescription
        }
    }
}
