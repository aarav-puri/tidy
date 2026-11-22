import SwiftUI
import QuickLook

struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    @State private var previewURL: URL?
    @State private var collapsed: Set<String> = []

    private var model: DuplicatesModel { app.duplicates }

    var body: some View {
        Group {
            if model.phase == .idle {
                IntroView(title: "Duplicate Finder", symbol: "square.on.square",
                          message: "Find identical copies of files. One copy is always kept.") {
                    Button("Scan") { model.scan() }
                        .floatingProminentButtonStyle()
                        .controlSize(.large)
                }
            } else {
                content
            }
        }
        .navigationTitle("Duplicates")
        .toolbar { toolbar }
        .quickLookPreview($previewURL)
        .alert("One Copy Must Be Kept", isPresented: Binding(get: { model.lastRefusal != nil }, set: { if !$0 { model.lastRefusal = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastRefusal ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu("Select", systemImage: "checklist") {
                Button("Select All but Oldest") { model.markAllButOldest() }
                Divider()
                Button("Deselect All") { model.clearMarks() }
            }
            .disabled(model.groups.isEmpty)
            .help("Select duplicates to remove")
            if model.phase.isScanning {
                Button("Stop", systemImage: "stop.fill") { model.cancel() }
            } else {
                Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.phase == .idle)
            }
        }
    }

    private var content: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Picker("Kind", selection: $model.filter) {
                    ForEach(DuplicateKindFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if model.phase.hasResults {
                    Text("\(Format.count(model.groups.count, singular: "group")) · \(Format.bytes(model.wastedSpace)) in extra copies")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            if case .scanning(let progress, let detail) = model.phase {
                ScanStatusView(title: "Finding Duplicates…", detail: detail, progress: progress) { model.cancel() }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            if model.filteredGroups.isEmpty && model.phase.hasResults {
                ContentUnavailableView("No Duplicates Found", systemImage: "checkmark.circle",
                                       description: Text("Checked \(Format.count(model.filesExamined, singular: "file")) larger than \(app.settings.duplicateMinimumMB) MB in your scan locations."))
            } else {
                List {
                    ForEach(model.filteredGroups) { group in
                        DisclosureGroup(isExpanded: expansion(group.id)) {
                            ForEach(group.files) { file in
                                DuplicateFileRow(file: file, isMarked: model.isMarked(file)) { value in
                                    model.setMarked(file, in: group, value)
                                }
                                .contextMenu { FileContextMenu(urls: [file.url], quickLook: { previewURL = $0 }) }
                            }
                        } label: {
                            DuplicateGroupHeader(group: group, markedCount: group.files.count(where: model.isMarked))
                                .contextMenu { Button("Quick Look") { previewURL = group.files.first?.url } }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.groups.isEmpty {
                SelectionActionBar(count: model.markedFiles.count, size: model.markedSize, actionTitle: "Remove…") {
                    model.requestRemoval()
                }
            }
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(id) }, set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } })
    }
}

private struct DuplicateGroupHeader: View {
    let group: DuplicateGroup
    let markedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: group.files[0].url, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.files[0].name).lineLimit(1).truncationMode(.middle)
                Text("\(group.files.count) identical copies · \(Format.bytes(group.size)) each")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if markedCount > 0 {
                Text("\(markedCount) selected").font(.caption).foregroundStyle(.secondary)
            }
            Text(Format.bytes(group.wastedSpace))
                .monospacedDigit()
                .help("Space used by the extra copies")
        }
        .padding(.vertical, 3)
    }
}

private struct DuplicateFileRow: View {
    let file: FoundFile
    let isMarked: Bool
    let onChange: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(file.name, isOn: Binding(get: { isMarked }, set: { onChange($0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.location).lineLimit(1).truncationMode(.head)
                Text("Modified \(Format.dateTime(file.modified))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isMarked {
                Text("Keep").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .glass(in: Capsule())
            }
            Button("Show in Finder", systemImage: "magnifyingglass.circle") { FileActions.reveal([file.url]) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name) in \(file.location)\(isMarked ? ", selected for removal" : ", kept")")
    }
}
