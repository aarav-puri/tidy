import SwiftUI
import QuickLook

struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Set<URL> = []
    @State private var sortOrder = [KeyPathComparator(\FoundFile.size, order: .reverse)]
    @State private var previewURL: URL?

    private var model: LargeFilesModel { app.largeFiles }

    var body: some View {
        Group {
            if model.phase == .idle {
                IntroView(title: "Large & Old Files", symbol: "doc.badge.clock",
                          message: "Find videos, disk images, and other big files you may have forgotten.") {
                    Button("Scan") { model.scan() }
                        .floatingProminentButtonStyle()
                        .controlSize(.large)
                }
            } else {
                content
            }
        }
        .navigationTitle("Large & Old Files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.phase.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                } else {
                    Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(model.phase == .idle)
                }
            }
        }
        .quickLookPreview($previewURL, in: model.filtered.map(\.url))
    }

    private var content: some View {
        @Bindable var model = model
        let rows = model.filtered.sorted(using: sortOrder)
        let selectedFiles = rows.filter { selection.contains($0.id) }
        return VStack(spacing: 0) {
            filterBar
            Divider()
            if case .scanning(_, let detail) = model.phase {
                ScanStatusView(title: "Searching…", detail: detail, progress: nil) { model.cancel() }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            if rows.isEmpty && !model.phase.isScanning {
                ContentUnavailableView("No Matching Files", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Try changing the filters."))
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { file in
                        HStack(spacing: 8) {
                            FileIcon(url: file.url)
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .width(min: 180, ideal: 280)
                    TableColumn("Size", value: \.size) { file in
                        Text(Format.bytes(file.size)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Kind", value: \.kind.title) { file in
                        Text(file.kind.title).foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 100)
                    TableColumn("Last Opened") { file in
                        Text(file.lastOpened.map { Format.date($0) } ?? "Unknown").foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("Modified", value: \.modified) { file in
                        Text(Format.date(file.modified)).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("Location", value: \.location) { file in
                        Text(file.location).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    .width(min: 120, ideal: 240)
                }
                .contextMenu(forSelectionType: URL.self) { ids in
                    if !ids.isEmpty {
                        FileContextMenu(urls: Array(ids), quickLook: { previewURL = $0 },
                                        onRemove: { model.requestRemoval(ids) })
                    }
                } primaryAction: { ids in
                    if let first = ids.first { FileActions.open(first) }
                }
                .onKeyPress(.space) {
                    guard let first = selectedFiles.first else { return .ignored }
                    previewURL = first.url
                    return .handled
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                SelectionActionBar(count: selectedFiles.count, size: selectedFiles.reduce(0) { $0 + $1.size },
                                   actionTitle: "Move to Trash…") {
                    model.requestRemoval(Set(selectedFiles.map(\.id)))
                }
            }
        }
    }

    private var filterBar: some View {
        @Bindable var model = model
        return HStack(spacing: 14) {
            Picker("Size", selection: $model.minimumMB) {
                ForEach(model.sizeOptions, id: \.self) { mb in
                    Text("Larger than \(Format.bytes(Int64(mb) * 1_000_000))").tag(mb)
                }
            }
            .fixedSize()
            Picker("Kind", selection: $model.kind) {
                Text("All Kinds").tag(FileKind?.none)
                Divider()
                ForEach(FileKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(FileKind?.some(kind))
                }
            }
            .fixedSize()
            Picker("Not Opened In", selection: $model.age) {
                ForEach(AgeFilter.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            .help("Based on when a file was last opened, or modified if unknown.")
            if model.roots.count > 1 {
                Picker("Location", selection: $model.location) {
                    Text("All Locations").tag(String?.none)
                    ForEach(model.roots, id: \.self) { root in
                        Text(Format.path(root)).tag(String?.some(root.path(percentEncoded: false)))
                    }
                }
                .fixedSize()
            }
            Spacer()
            Text("\(Format.count(model.filtered.count, singular: "file")) · \(Format.bytes(model.filtered.reduce(0) { $0 + $1.size }))")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
