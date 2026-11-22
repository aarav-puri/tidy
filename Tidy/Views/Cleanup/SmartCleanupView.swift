import SwiftUI
import QuickLook

struct SmartCleanupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: URL?
    @State private var showInspector = true
    @State private var expanded: Set<CleanupCategoryKind> = []
    @State private var previewURL: URL?
    @State private var trashError: String?
    @State private var confirmEmptyTrash = false

    private var model: SmartCleanupModel { app.cleanup }

    var body: some View {
        Group {
            if !model.hasResults && !model.phase.isScanning {
                IntroView(title: "Smart Cleanup", symbol: "eraser",
                          message: "Find caches, logs, and other files you can safely remove.") {
                    Button("Scan") { model.scan() }
                        .floatingProminentButtonStyle()
                        .controlSize(.large)
                }
            } else {
                results
            }
        }
        .navigationTitle("Smart Cleanup")
        .navigationSubtitle(model.lastScan.map { "Last scanned \(Format.relative($0))" } ?? "")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            CleanupInspector(item: model.item(selection), previewURL: $previewURL)
                .panelBackdrop()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
        } message: {
            Text("You can't undo this action.")
        }
        .alert("Couldn't Empty the Trash", isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
            Button("OK", role: .cancel) {}
            Button("Open Automation Settings") { Permissions.openAutomationSettings() }
        } message: {
            Text(trashError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.phase.isScanning {
                Button("Stop Scan", systemImage: "stop.fill") { model.cancel() }
            } else {
                Button(model.hasResults ? "Rescan" : "Scan", systemImage: "arrow.clockwise") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Scan again")
            }
            Menu("Select", systemImage: "checklist") {
                Button("Select All Recommended") { model.setAll(true, risk: .recommended) }
                Button("Select Everything") { model.setAll(true) }
                Divider()
                Button("Deselect All") { model.setAll(false) }
            }
            .disabled(model.categories.isEmpty)
            .help("Change which items are selected")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
        }
    }

    private var results: some View {
        @Bindable var model = model
        return List(selection: $selection) {
            Section {
                header
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                if !model.unavailable.isEmpty {
                    FullDiskAccessBanner(message: model.unavailable.joined(separator: " "))
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
            }
            ForEach($model.categories) { $category in
                DisclosureGroup(isExpanded: expansion(category.kind)) {
                    ForEach($category.items) { $item in
                        CleanupItemRow(item: $item)
                            .tag(item.id)
                            .contextMenu { FileContextMenu(urls: [item.url], quickLook: { previewURL = $0 }) }
                    }
                } label: {
                    CategoryRow(category: $category)
                        .selectionDisabled()
                }
            }
            if let trash = model.trashSize, trash > 0 {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "trash").frame(width: 20).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trash")
                            Text("Items in the Trash").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(trash)).monospacedDigit().foregroundStyle(.secondary)
                        Button("Empty Trash…") { confirmEmptyTrash = true }
                    }
                    .selectionDisabled()
                }
            }
            if !model.protectedItems.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.protectedItems) { item in
                            CleanupItemRow(item: .constant(item)).tag(item.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").frame(width: 20).foregroundStyle(.secondary)
                            Text("Protected")
                            Spacer()
                            Text(Format.count(model.protectedItems.count, singular: "item")).foregroundStyle(.secondary)
                        }
                        .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            if model.phase.hasResults && model.candidateCount > 0 {
                SelectionActionBar(count: model.selectedCount, size: model.selectedSize, actionTitle: "Clean Up…") {
                    model.requestCleanup()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MotionAware.animation(reduceMotion: reduceMotion), value: model.categories.count)
    }

    @ViewBuilder
    private var header: some View {
        switch model.phase {
        case .scanning(let progress, let detail):
            ScanStatusView(title: "Scanning…", detail: detail, progress: progress) { model.cancel() }
                .padding(.vertical, 8)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase == .cancelled ? "Scan Stopped" : model.candidateCount == 0 ? "Scan Complete" : "You can free up")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if model.candidateCount == 0 {
                    GlassText("Nothing to clean up", size: 30)
                } else {
                    GlassText(Format.bytes(model.reclaimable), size: 40)
                        .accessibilityLabel("You can free up to \(Format.bytes(model.reclaimable))")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func expansion(_ kind: CleanupCategoryKind) -> Binding<Bool> {
        Binding(get: { expanded.contains(kind) }, set: { if $0 { expanded.insert(kind) } else { expanded.remove(kind) } })
    }

    private func emptyTrash() {
        Task {
            do {
                try await app.emptyTrash(knownSize: model.trashSize)
                model.trashEmptied()
            } catch {
                trashError = error.localizedDescription
            }
        }
    }
}

private struct CategoryRow: View {
    @Binding var category: CleanupCategoryResult

    var body: some View {
        HStack(spacing: 10) {
            Toggle(sources: $category.items, isOn: \.isSelected) { Text(category.kind.title) }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Select all \(category.kind.title)")
            Image(systemName: category.kind.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(category.kind.title)
                .help(category.kind.explanation)
            Spacer(minLength: 12)
            Text(Format.count(category.items.count, singular: "item"))
                .font(.callout).foregroundStyle(.secondary)
            Text(Format.bytes(category.items.reduce(0) { $0 + $1.size }))
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

private struct CleanupItemRow: View {
    @Binding var item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            if item.isSelectable {
                Toggle(item.name, isOn: $item.isSelected)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.tertiary).frame(width: 14)
            }
            FileIcon(url: item.url)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(Format.parentPath(item.url)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 12)
            RiskLabel(risk: item.risk, compact: true)
            Text(Format.bytes(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(Format.bytes(item.size)), \(item.risk.title)")
    }
}

/// The detail pane shown for the selected cleanup item.
private struct CleanupInspector: View {
    let item: CleanupItem?
    @Binding var previewURL: URL?

    var body: some View {
        if let item {
            Form {
                Section {
                    VStack(spacing: 8) {
                        FileIcon(url: item.url, size: 64)
                        Text(item.name).font(.headline).multilineTextAlignment(.center).lineLimit(3)
                        Text(Format.bytes(item.size)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                Section("Assessment") {
                    LabeledContent("Classification") { RiskLabel(risk: item.risk) }
                    Text(item.reason).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Details") {
                    LabeledContent("Category", value: item.category.title)
                    LabeledContent("Modified", value: Format.dateTime(item.modified))
                    LabeledContent("Location") {
                        Text(Format.parentPath(item.url)).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Button("Show in Finder") { FileActions.reveal([item.url]) }
                    Button("Quick Look") { previewURL = item.url }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing",
                                   description: Text("Select an item to see details."))
        }
    }
}

/// A floating summary of the current selection with a primary action,
/// placed on the control layer above content.
struct SelectionActionBar: View {
    let count: Int
    let size: Int64
    let actionTitle: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 0 ? "Nothing selected" : "\(Format.count(count, singular: "item")) selected")
                    .font(.callout.weight(.medium))
                Text(Format.bytes(size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button(actionTitle, action: action)
                .floatingProminentButtonStyle()
                .controlSize(.large)
                .disabled(count == 0 || disabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .controlGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
