import SwiftUI
import QuickLook

struct DownloadsView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Set<URL> = []
    @State private var sortOrder = [KeyPathComparator(\DownloadItem.size, order: .reverse)]
    @State private var previewURL: URL?

    private var model: DownloadsModel { app.downloads }

    var body: some View {
        @Bindable var model = model
        let rows = model.filtered.sorted(using: sortOrder)
        let selected = rows.filter { selection.contains($0.id) }
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $model.filter) {
                    ForEach(DownloadFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("\(Format.count(model.items.count, singular: "item")) · \(Format.bytes(model.totalSize))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .controlSize(.small)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            if model.accessDenied {
                ContentUnavailableView {
                    Label("No Access to Downloads", systemImage: "lock")
                } description: {
                    Text("Allow access in System Settings > Privacy & Security > Files & Folders.")
                } actions: {
                    Button("Open Privacy Settings") { Permissions.openFullDiskAccessSettings() }
                    Button("Try Again") { model.load() }
                }
            } else if rows.isEmpty && model.phase.hasResults {
                ContentUnavailableView("Nothing Here", systemImage: "arrow.down.circle",
                                       description: Text(model.filter == .all ? "Your Downloads folder is empty." : "No downloads match this filter."))
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { item in
                        HStack(spacing: 8) {
                            FileIcon(url: item.url)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                                .help(model.note(for: item) ?? "")
                        }
                    }
                    .width(min: 200, ideal: 320)
                    TableColumn("Size", value: \.size) { Text(Format.bytes($0.size)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("Kind", value: \.kindDescription) { Text($0.kindDescription).foregroundStyle(.secondary) }
                        .width(min: 80, ideal: 130)
                    TableColumn("Date Added") { item in
                        Text(Format.date(item.added ?? item.modified)).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("Downloaded From") { item in
                        Text(item.source ?? "Unknown").foregroundStyle(.secondary).lineLimit(1)
                    }
                    .width(min: 100, ideal: 160)
                }
                .contextMenu(forSelectionType: URL.self) { ids in
                    if !ids.isEmpty {
                        FileContextMenu(urls: Array(ids), quickLook: { previewURL = $0 }, onRemove: { model.requestRemoval(ids) })
                    }
                } primaryAction: { ids in
                    if let first = ids.first { FileActions.open(first) }
                }
                .onKeyPress(.space) {
                    guard let first = selected.first else { return .ignored }
                    previewURL = first.url
                    return .handled
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                SelectionActionBar(count: selected.count, size: selected.reduce(0) { $0 + $1.size }, actionTitle: "Move to Trash…") {
                    model.requestRemoval(Set(selected.map(\.id)))
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open in Finder", systemImage: "folder") { FileActions.open(DownloadsScanner.folder) }
                Button("Refresh", systemImage: "arrow.clockwise") { model.load() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .quickLookPreview($previewURL, in: rows.map(\.url))
        .task { if model.phase == .idle { model.load() } }
    }
}
