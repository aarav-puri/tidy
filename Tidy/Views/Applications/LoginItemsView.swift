import SwiftUI

struct LoginItemsView: View {
    @Environment(AppModel.self) private var app
    @State private var items: [LaunchItem] = []
    @State private var loading = false
    @State private var openAtLogin: [OpenAtLoginApp]?
    @State private var openAtLoginError: String?
    @State private var tidyAtLogin = LoginItemsService.tidyLaunchesAtLogin

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "power.circle").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Login & Background Items").font(.headline)
                }
                .padding(.vertical, 4)
                HStack {
                    Spacer()
                    Button("Open Login Items Settings…") { Permissions.openLoginItemsSettings() }
                        .floatingProminentButtonStyle()
                }
            }

            Section {
                if let openAtLogin {
                    if openAtLogin.isEmpty {
                        Text("No apps are set to open at login.").foregroundStyle(.secondary)
                    }
                    ForEach(openAtLogin) { item in
                        HStack {
                            if let path = item.path { FileIcon(url: URL(filePath: path), size: 20) }
                            Text(item.name)
                            Spacer()
                            if let path = item.path {
                                Button("Show in Finder") { FileActions.reveal([URL(filePath: path)]) }.controlSize(.small)
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Show Apps") { loadOpenAtLogin() }
                    }
                }
                if let openAtLoginError {
                    Label(openAtLoginError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                LabeledContent("Open Tidy at Login") {
                    Toggle("Open Tidy at Login", isOn: $tidyAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: tidyAtLogin) { _, value in
                            try? LoginItemsService.setTidyLaunchesAtLogin(value)
                            tidyAtLogin = LoginItemsService.tidyLaunchesAtLogin
                        }
                }
            } header: {
                Text("Open at Login")
            }

            ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                let scoped = items.filter { $0.scope == scope }
                Section {
                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if scoped.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(scoped) { item in LaunchItemRow(item: item) }
                } header: {
                    Text(scope.title)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Login Items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .task { if items.isEmpty { await load() } }
    }

    private func load() async {
        #if DEBUG
        if app.isDemo {
            items = DemoData.launchItems
            openAtLogin = DemoData.openAtLogin
            tidyAtLogin = true
            return
        }
        #endif
        loading = true
        items = await LoginItemsService.launchItems()
        loading = false
        tidyAtLogin = LoginItemsService.tidyLaunchesAtLogin
    }

    private func loadOpenAtLogin() {
        openAtLoginError = nil
        Task {
            do { openAtLogin = try await LoginItemsService.openAtLoginApps() }
            catch { openAtLoginError = error.localizedDescription }
        }
    }
}

private struct LaunchItemRow: View {
    let item: LaunchItem

    var body: some View {
        HStack(spacing: 10) {
            if let appURL = item.appURL {
                FileIcon(url: appURL, size: 24)
            } else {
                Image(systemName: "gearshape.2").frame(width: 24).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).lineLimit(1)
                Text(item.developer.map { "\($0) · \(item.label)" } ?? item.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            status
            Menu {
                Button("Show Configuration in Finder") { FileActions.reveal([item.plist]) }
                if let program = item.program {
                    Button("Show Program in Finder") { FileActions.reveal([URL(filePath: program)]) }
                }
                Divider()
                Button("Manage in System Settings…") { Permissions.openLoginItemsSettings() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(item.displayName)")
        }
    }

    @ViewBuilder
    private var status: some View {
        let (text, color): (String, Color) = {
            if item.disabledInPlist { return ("Disabled", .secondary) }
            if item.isRunning { return ("Running", .green) }
            switch item.isLoaded {
            case .some(true): return ("Loaded", .secondary)
            case .some(false): return ("Not Loaded", .secondary)
            case .none: return ("Status Unknown", .secondary)
            }
        }()
        HStack(spacing: 5) {
            Circle().fill(color == .green ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .help(item.runAtLoad ? "Starts automatically" : "Starts on demand")
    }
}
