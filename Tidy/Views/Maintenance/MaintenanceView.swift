import SwiftUI

struct MaintenanceView: View {
    @Environment(AppModel.self) private var app
    @State private var health: DiskHealth?
    @State private var cacheSize: Int64?
    @State private var tempSize: Int64?
    @State private var trashSize: Int64?
    @State private var trashMeasured = false
    @State private var checking = false
    @State private var confirmEmptyTrash = false
    @State private var trashError: String?

    var body: some View {
        Form {
            Section {
                CheckRow(title: "Startup Disk Space", symbol: "internaldrive", status: spaceStatus, detail: spaceDetail) {
                    Button("Review Storage") { app.selection = .storageExplorer }
                }
                CheckRow(title: "Storage Health", symbol: "heart.text.square", status: healthStatus, detail: healthDetail) {
                    Button("Open Disk Utility") { Permissions.openSystemApp(bundleIdentifier: "com.apple.DiskUtility") }
                }
                CheckRow(title: "App Caches", symbol: "shippingbox", status: cacheStatus,
                         detail: cacheSize.map { "\(Format.bytes($0)) used by app caches." } ?? "Checking…") {
                    Button("Review") { app.selection = .smartCleanup }
                }
                CheckRow(title: "Temporary Files", symbol: "clock.arrow.circlepath", status: tempStatus,
                         detail: tempSize.map { "\(Format.bytes($0)). Cleared when you restart." } ?? "Checking…") {
                    Button("Review") { app.selection = .smartCleanup }
                }
                CheckRow(title: "Trash", symbol: "trash", status: trashStatus, detail: trashDetail) {
                    Button("Empty Trash…") { confirmEmptyTrash = true }
                }
                CheckRow(title: "Login & Background Items", symbol: "power", status: .info, detail: nil) {
                    Button("Review") { app.selection = .loginItems }
                }
            } header: {
                HStack {
                    Text("Checks")
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                }
            }

            Section("macOS Utilities") {
                UtilityRow(title: "Disk Utility", bundleID: "com.apple.DiskUtility")
                UtilityRow(title: "Activity Monitor", bundleID: "com.apple.ActivityMonitor")
                UtilityRow(title: "Console", bundleID: "com.apple.Console")
                UtilityRow(title: "System Information", bundleID: "com.apple.SystemProfiler")
                LabeledContent {
                    Button("Open") { Permissions.openStorageSettings() }
                } label: {
                    Text("Storage Settings")
                }
                LabeledContent {
                    Button("Open") { Permissions.openSoftwareUpdate() }
                } label: {
                    Text("Software Update")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Run Checks Again", systemImage: "arrow.clockwise") { Task { await runChecks() } }
                    .disabled(checking)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .task { await runChecks() }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    do {
                        try await app.emptyTrash(knownSize: trashSize)
                        await runChecks()
                    } catch { trashError = error.localizedDescription }
                }
            }
        } message: {
            Text("You can't undo this action.")
        }
        .alert("Couldn't Empty the Trash", isPresented: Binding(get: { trashError != nil }, set: { if !$0 { trashError = nil } })) {
            Button("OK", role: .cancel) {}
            Button("Open Automation Settings") { Permissions.openAutomationSettings() }
        } message: { Text(trashError ?? "") }
    }

    private func runChecks() async {
        checking = true
        #if DEBUG
        if app.isDemo {
            health = await DiskHealthService.startupDisk()
            cacheSize = DemoData.gb(9.71)
            tempSize = DemoData.gb(1.58)
            trashSize = DemoData.gb(3.6)
            trashMeasured = true
            checking = false
            return
        }
        #endif
        app.refreshVolume()
        async let diskHealth = DiskHealthService.startupDisk()
        let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64, Int64?) in
            let caches = FileSystem.usage(of: FileSystem.library.appending(path: "Caches")).bytes
            let temp = FileSystem.usage(of: URL(filePath: NSTemporaryDirectory())).bytes
            return (caches, temp, TrashService.measure())
        }.value
        health = await diskHealth
        cacheSize = sizes.0
        tempSize = sizes.1
        trashSize = sizes.2
        trashMeasured = sizes.2 != nil
        checking = false
    }

    private var spaceStatus: CheckStatus {
        guard let v = app.volume else { return .unknown }
        let freeFraction = 1 - v.utilization
        if v.available < 10_000_000_000 || freeFraction < 0.05 { return .attention }
        if v.available < 25_000_000_000 || freeFraction < 0.12 { return .warning }
        return .good
    }

    private var spaceDetail: String {
        guard let v = app.volume else { return "Unavailable" }
        let base = "\(Format.bytes(v.available)) available of \(Format.bytes(v.total))."
        switch spaceStatus {
        case .attention: return base + " macOS needs free space for updates, virtual memory, and snapshots. Free up space soon."
        case .warning: return base + " Consider freeing some space to leave room for updates."
        default: return base + " There's plenty of room."
        }
    }

    private var healthStatus: CheckStatus {
        guard let s = health?.smartStatus else { return health == nil ? .unknown : .info }
        return s == "Verified" ? .good : (s == "Not Supported" ? .info : .attention)
    }

    private var healthDetail: String {
        guard let health else { return "Checking…" }
        var parts: [String] = []
        if let s = health.smartStatus {
            parts.append(s == "Verified" ? "No problems reported." :
                            s == "Not Supported" ? "Not reported by this drive." : "Status: \(s). Back up your data and contact Apple Support.")
        } else {
            parts.append("Not available.")
        }
        if let fs = health.fileSystem { parts.append("Format: \(fs).") }
        if let encrypted = health.isEncrypted { parts.append(encrypted ? "FileVault is on." : "FileVault is off.") }
        return parts.joined(separator: " ")
    }

    private var cacheStatus: CheckStatus {
        guard let cacheSize else { return .unknown }
        return cacheSize > 10_000_000_000 ? .warning : .good
    }

    private var tempStatus: CheckStatus {
        guard let tempSize else { return .unknown }
        return tempSize > 5_000_000_000 ? .warning : .good
    }

    private var trashStatus: CheckStatus {
        guard let trashSize else { return checking ? .unknown : .info }
        return trashSize > 5_000_000_000 ? .warning : .good
    }

    private var trashDetail: String {
        if let trashSize { return trashSize == 0 ? "The Trash is empty." : "\(Format.bytes(trashSize)) in the Trash." }
        return checking ? "Checking…" : "Size requires Full Disk Access."
    }
}

enum CheckStatus {
    case good, warning, attention, info, unknown

    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .unknown: "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .attention: .red
        case .info: .secondary
        case .unknown: .secondary
        }
    }
}

private struct CheckRow<Action: View>: View {
    let title: String
    let symbol: String
    let status: CheckStatus
    let detail: String?
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 26).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                    Image(systemName: status.symbol).foregroundStyle(status.color).font(.caption)
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            action.controlSize(.small)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct UtilityRow: View {
    let title: String
    let bundleID: String

    var body: some View {
        LabeledContent {
            Button("Open") { Permissions.openSystemApp(bundleIdentifier: bundleID) }
        } label: {
            HStack(spacing: 10) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    FileIcon(url: url, size: 24)
                }
                Text(title)
            }
        }
    }
}
