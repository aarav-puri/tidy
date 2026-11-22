import SwiftUI

struct AppManagerView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: InstalledApp.ID?
    @State private var sortOrder = [KeyPathComparator(\InstalledApp.name, comparator: .localizedStandard)]
    @State private var showInspector = true

    private var model: AppManagerModel { app.apps }

    var body: some View {
        @Bindable var model = model
        let rows = sorted(model.visibleApps)
        VStack(spacing: 0) {
            if case .scanning(let progress, let detail) = model.phase {
                ScanStatusView(title: "Reading Applications…", detail: detail, progress: progress)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { item in
                    HStack(spacing: 8) {
                        FileIcon(url: item.url, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name)
                            if item.isSystemApp {
                                Text("Included with macOS").font(.caption).foregroundStyle(.secondary)
                            } else if item.isAppStore {
                                Text("App Store").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .width(min: 180, ideal: 240)
                TableColumn("Developer") { item in
                    Text(item.developer ?? "—").foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 100, ideal: 160)
                TableColumn("Version") { item in
                    Text(item.version ?? "—").foregroundStyle(.secondary).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
                TableColumn("Size", value: \.sortSize) { item in
                    Text(item.size.map(Format.bytes) ?? "Measuring…").monospacedDigit()
                        .foregroundStyle(item.size == nil ? .tertiary : .primary)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Last Opened", value: \.sortLastUsed) { item in
                    Text(item.lastUsed.map { Format.date($0) } ?? "Unknown").foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110)
            }
            .contextMenu(forSelectionType: InstalledApp.ID.self) { ids in
                if let id = ids.first, let item = model.apps.first(where: { $0.id == id }) {
                    Button("Open", systemImage: "arrow.up.forward.app") { FileActions.open(item.url) }
                    Button("Show in Finder", systemImage: "folder") { FileActions.reveal([item.url]) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = model.apps.first(where: { $0.id == id }) { FileActions.open(item.url) }
            }
        }
        .navigationTitle("App Manager")
        .navigationSubtitle(model.apps.isEmpty ? "" : "\(Format.count(model.visibleApps.count, singular: "app")) · \(Format.bytes(model.totalSize))")
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search Apps")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $model.showSystemApps) {
                    Label("Show macOS Apps", systemImage: "apple.logo")
                }
                .help("Show apps included with macOS")
                Button("Refresh", systemImage: "arrow.clockwise") { model.load() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let id = selection, let item = model.apps.first(where: { $0.id == id }) {
                    AppInspector(item: item)
                } else {
                    ContentUnavailableView("No App Selected", systemImage: "square.grid.2x2",
                                           description: Text("Select an app to see details."))
                }
            }
            .panelBackdrop()
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .task { if model.phase == .idle { model.load() } }
    }

    private func sorted(_ apps: [InstalledApp]) -> [InstalledApp] {
        apps.sorted(using: sortOrder)
    }
}

extension InstalledApp {
    var sortSize: Int64 { size ?? -1 }
    var sortLastUsed: Date { lastUsed ?? .distantPast }
}

private struct AppInspector: View {
    @Environment(AppModel.self) private var app
    let item: InstalledApp

    private var model: AppManagerModel { app.apps }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(spacing: 6) {
                    FileIcon(url: item.url, size: 72)
                    Text(item.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    if let version = item.version { Text("Version \(version)").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                LabeledContent("Developer", value: item.developer ?? "Unknown")
                LabeledContent("Identifier") { Text(item.bundleIdentifier ?? "None").textSelection(.enabled) }
                LabeledContent("App Size", value: item.size.map(Format.bytes) ?? "Measuring…")
                LabeledContent("Related Data", value: item.relatedSize.map(Format.bytes) ?? "—")
                LabeledContent("Last Opened", value: item.lastUsed.map { Format.dateTime($0) } ?? "Unknown")
                LabeledContent("Location") { Text(Format.parentPath(item.url)).multilineTextAlignment(.trailing) }
            }

            if let reason = item.protectionReason {
                Section {
                    Label(reason, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if model.loadingAssociated.contains(item.id) {
                        HStack { ProgressView().controlSize(.small); Text("Finding related files…").foregroundStyle(.secondary) }
                    } else if let files = model.associated[item.id] {
                        ForEach(AssociatedKind.allCases) { kind in
                            let indices = files.indices.filter { files[$0].kind == kind }
                            if !indices.isEmpty {
                                ForEach(indices, id: \.self) { index in
                                    AssociatedFileRow(file: Binding(
                                        get: { model.associated[item.id]?[index] ?? files[index] },
                                        set: { model.associated[item.id]?[index] = $0 }))
                                }
                            }
                        }
                        if files.isEmpty { Text("No related files found.").foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("Files to Remove")
                } footer: {
                    Text("Related files are matched by the app's identifier (\(item.bundleIdentifier ?? "unknown")) or its developer team. Files with only a similar name are listed but not selected. Your documents are never included.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    if let running = model.runningInstance(of: item) {
                        HStack {
                            Label("\(item.name) is open.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Spacer()
                            Button("Quit \(item.name)") { running.terminate() }
                        }
                    }
                    HStack {
                        Button("Show in Finder") { FileActions.reveal([item.url]) }
                        Spacer()
                        let selected = model.associated[item.id]?.filter(\.isSelected) ?? []
                        Button(selected.contains { $0.kind == .bundle } ? "Uninstall…" : "Remove…", role: .destructive) {
                            model.requestUninstall(item)
                        }
                        .disabled(selected.isEmpty || model.runningInstance(of: item) != nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: item.id) { if !item.isProtected { model.loadAssociated(for: item) } }
    }
}

struct AssociatedFileRow: View {
    @Binding var file: AssociatedFile

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(file.url.lastPathComponent, isOn: $file.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: file.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.kind == .bundle ? "Application" : file.url.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(file.kind.title) · \(Format.parentPath(file.url))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                if let caution = file.kind.caution {
                    Text(caution).font(.caption).foregroundStyle(.orange)
                }
            }
            .help(file.evidence)
            Spacer()
            Text(Format.bytes(file.size)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu { FileContextMenu(urls: [file.url]) }
    }
}
