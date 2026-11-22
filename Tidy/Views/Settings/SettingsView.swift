import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Scanning", systemImage: "magnifyingglass") { ScanningSettings() }
            Tab("Cleanup", systemImage: "trash") { CleanupSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .scenePadding()
        .frame(width: 560)
        .frame(minHeight: 420)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @State private var launchAtLogin = LoginItemsService.tidyLaunchesAtLogin
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Open Tidy at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        do { try LoginItemsService.setTidyLaunchesAtLogin(value) } catch { loginError = error.localizedDescription }
                        launchAtLogin = LoginItemsService.tidyLaunchesAtLogin
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Show in menu bar", isOn: $settings.showMenuBarExtra)
            }
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Notify me when a scan finishes", isOn: $settings.notifyWhenScansFinish)
                    .onChange(of: settings.notifyWhenScansFinish) { _, value in
                        if value { Task { _ = await NotificationService.requestAuthorization() } }
                    }
            } header: {
                Text("Notifications")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScanningSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                PathListEditor(paths: $settings.scanLocations, emptyText: "Your home folder")
            } header: {
                Text("Scan Locations")
            }
            Section {
                PathListEditor(paths: $settings.excludedPaths, emptyText: "No excluded folders.")
            } header: {
                Text("Excluded Folders")
            }
            Section("Thresholds") {
                Picker("Large files are at least", selection: $settings.largeFileMinimumMB) {
                    ForEach([50, 100, 250, 500, 1_000], id: \.self) { Text(Format.bytes(Int64($0) * 1_000_000)).tag($0) }
                }
                Picker("Check duplicates larger than", selection: $settings.duplicateMinimumMB) {
                    ForEach([0, 1, 10, 100], id: \.self) { Text($0 == 0 ? "Any size" : Format.bytes(Int64($0) * 1_000_000)).tag($0) }
                }
            }
            Section {
                Picker("Remind me to scan", selection: $settings.scanReminder) {
                    ForEach(ScanReminder.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.scanReminder) { _, value in
                    Task {
                        if value != .never { _ = await NotificationService.requestAuthorization() }
                        NotificationService.scheduleReminder(value)
                    }
                }
            } header: {
                Text("Scan Frequency")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CleanupSettings: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("When removing items", selection: $settings.removalMode) {
                    Text("Move to Trash (Recommended)").tag(RemovalMode.moveToTrash)
                    Text("Delete Immediately").tag(RemovalMode.deleteImmediately)
                }
                if settings.removalMode == .deleteImmediately {
                    Label("Deleted items can't be recovered. Apps always go to the Trash.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Ask before moving items to the Trash", isOn: $settings.confirmMoveToTrash)
                    .disabled(settings.removalMode == .deleteImmediately)
            } header: {
                Text("Removal")
            }
            Section {
                Toggle("Keep cleanup history", isOn: $settings.keepHistory)
                LabeledContent("Records", value: "\(app.history.entries.count)")
                Button("Clear History…") { confirmClear = true }
                    .disabled(app.history.entries.isEmpty)
            } header: {
                Text("Cleanup History")
            }
            Section {
                PathListEditor(paths: $settings.protectedPaths, emptyText: "No additional protected locations.")
            } header: {
                Text("Protected Locations")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear History?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { app.history.clear() }
        }
    }
}

private struct AboutSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tidy").font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Privacy") {
                Label("All scanning happens on this Mac.", systemImage: "desktopcomputer")
                Label("Nothing leaves your Mac.", systemImage: "network.slash")
                Label("No analytics are collected.", systemImage: "chart.bar.xaxis")
                LabeledContent("Full Disk Access", value: app.hasFullDiskAccess ? "Granted" : "Not granted")
                Button("Open Privacy & Security Settings") { Permissions.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

/// An editable list of folders, in the style of System Settings lists with +/− buttons.
struct PathListEditor: View {
    @Binding var paths: [String]
    let emptyText: String
    @State private var selection: String?
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                if paths.isEmpty {
                    Text(emptyText).foregroundStyle(.secondary).selectionDisabled()
                }
                ForEach(paths, id: \.self) { path in
                    HStack(spacing: 8) {
                        FileIcon(url: URL(filePath: path), size: 16)
                        Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    }
                    .tag(path)
                }
            }
            .frame(minHeight: 70, maxHeight: 130)
            HStack(spacing: 0) {
                Button { choosing = true } label: { Image(systemName: "plus").frame(width: 20, height: 16) }
                    .accessibilityLabel("Add Folder")
                Divider().frame(height: 14)
                Button {
                    if let selection { paths.removeAll { $0 == selection } }
                    selection = nil
                } label: { Image(systemName: "minus").frame(width: 20, height: 16) }
                    .disabled(selection == nil)
                    .accessibilityLabel("Remove Folder")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let path = url.path(percentEncoded: false)
                    if !paths.contains(path) { paths.append(path) }
                }
            }
        }
    }
}
