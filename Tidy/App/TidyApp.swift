import SwiftUI

@main
struct TidyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Tidy", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands { TidyCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra("Tidy", image: "MenuBarIcon", isInserted: Binding(
            get: { model.settings.showMenuBarExtra },
            set: { model.settings.showMenuBarExtra = $0 })) {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct TidyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Scan") {
            Button("Scan Mac") { model.selection = .dashboard; model.scanMac() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.isScanningMac)
            Button("Stop Scanning") { model.cancelScanMac() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isScanningMac)
            Divider()
            Button("Smart Cleanup") { model.selection = .smartCleanup; model.cleanup.scan() }
            Button("Large & Old Files") { model.selection = .largeFiles; model.largeFiles.scan() }
            Button("Duplicates") { model.selection = .duplicates; model.duplicates.scan() }
            Button("App Leftovers") { model.selection = .leftovers; model.leftovers.scan() }
        }
        CommandGroup(after: .sidebar) {
            Divider()
            let shortcuts: [(SidebarItem, KeyEquivalent)] = [
                (.dashboard, "1"), (.smartCleanup, "2"), (.storageExplorer, "3"), (.largeFiles, "4"),
                (.duplicates, "5"), (.appManager, "6"), (.performance, "7"), (.maintenance, "8"), (.history, "9"),
            ]
            ForEach(shortcuts, id: \.0) { item, key in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(key, modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button("Privacy & Security Settings…") { Permissions.openFullDiskAccessSettings() }
        }
    }
}
