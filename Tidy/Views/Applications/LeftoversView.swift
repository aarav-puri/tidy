import SwiftUI

struct LeftoversView: View {
    @Environment(AppModel.self) private var app
    @State private var expanded: Set<String> = []

    private var model: LeftoversModel { app.leftovers }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.phase == .idle {
                IntroView(title: "App Leftovers", symbol: "puzzlepiece.extension",
                          message: "Find files left behind by apps you've deleted.") {
                    Button("Scan") { model.scan() }
                        .floatingProminentButtonStyle()
                        .controlSize(.large)
                }
            } else {
                List {
                    Section {
                        if case .scanning(_, let detail) = model.phase {
                            ScanStatusView(title: "Scanning…", detail: detail, progress: nil) { model.cancel() }
                                .padding(.vertical, 6)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.groups.isEmpty ? "No Leftovers Found" : "\(Format.bytes(model.totalSize)) from \(Format.count(model.groups.count, singular: "removed app"))")
                                    .font(.title2.weight(.semibold))
                            }
                            .padding(.vertical, 6)
                        }
                        if model.containersSkipped {
                            FullDiskAccessBanner(message: "App containers need Full Disk Access to be checked.")
                        }
                    }
                    ForEach($model.groups) { $group in
                        DisclosureGroup(isExpanded: expansion(group.id)) {
                            ForEach($group.items) { $file in
                                AssociatedFileRow(file: $file)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Toggle(sources: $group.items, isOn: \.isSelected) { Text(group.identifier) }
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                Image(systemName: "app.dashed").font(.title3).foregroundStyle(.secondary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.identifier).lineLimit(1)
                                    Text(Format.count(group.items.count, singular: "item") + (group.lastModified.map { " · last modified \(Format.date($0))" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ConfidenceLabel(confidence: group.confidence)
                                Text(Format.bytes(group.totalSize)).monospacedDigit().frame(minWidth: 70, alignment: .trailing)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    if !model.groups.isEmpty {
                        SelectionActionBar(count: model.selectedFiles.count, size: model.selectedFiles.reduce(0) { $0 + $1.size },
                                           actionTitle: "Remove…") { model.requestRemoval() }
                    }
                }
            }
        }
        .navigationTitle("App Leftovers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Select", systemImage: "checklist") {
                    Button("Select High-Confidence Items") { model.selectHighConfidence() }
                    Button("Deselect All") { model.deselectAll() }
                }
                .disabled(model.groups.isEmpty)
                Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                    .disabled(model.phase.isScanning)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) }, set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }
}

private struct ConfidenceLabel: View {
    let confidence: LeftoverGroup.Confidence

    var body: some View {
        Text("\(confidence.title) confidence")
            .font(.caption)
            .foregroundStyle(confidence == .high ? .primary : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .glass(in: Capsule(), tint: confidence == .high ? Color.accentColor.opacity(0.3) : nil)
            .help(confidence == .high
                  ? "No app from this developer is installed, and the files haven't changed in 30 days."
                  : "May still be used by another app or tool.")
    }
}
