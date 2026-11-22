import Foundation
import ServiceManagement

struct LaunchItem: Identifiable, Sendable, Hashable {
    enum Scope: String, Sendable, CaseIterable {
        case userAgent, systemAgent, systemDaemon

        var title: String {
            switch self {
            case .userAgent: "Your Launch Agents"
            case .systemAgent: "Launch Agents for All Users"
            case .systemDaemon: "System Background Services"
            }
        }

        var folder: URL {
            switch self {
            case .userAgent: FileSystem.library.appending(path: "LaunchAgents", directoryHint: .isDirectory)
            case .systemAgent: URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory)
            case .systemDaemon: URL(filePath: "/Library/LaunchDaemons", directoryHint: .isDirectory)
            }
        }

        var footnote: String {
            switch self {
            case .userAgent: ""
            case .systemAgent: ""
            case .systemDaemon: ""
            }
        }
    }

    var id: String { plist.path(percentEncoded: false) }
    let plist: URL
    let label: String
    let program: String?
    let scope: Scope
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabledInPlist: Bool
    let isLoaded: Bool?
    let isRunning: Bool
    let appURL: URL?
    let developer: String?

    var displayName: String {
        if let appURL { return appURL.deletingPathExtension().lastPathComponent }
        return label
    }
}

struct OpenAtLoginApp: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let path: String?
}

enum LoginItemsService {
    static func launchItems() async -> [LaunchItem] {
        let userList = await Shell.run("/bin/launchctl", ["list"])
        var loaded: [String: Bool] = [:] // label -> running
        for line in userList.output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            loaded[String(parts[2])] = parts[0] != "-"
        }
        var items: [LaunchItem] = []
        for scope in LaunchItem.Scope.allCases {
            for url in FileSystem.children(of: scope.folder) ?? [] where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = plist["Label"] as? String else { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                var isLoaded: Bool?
                var running = false
                if scope == .systemDaemon {
                    let result = await Shell.run("/bin/launchctl", ["print", "system/\(label)"])
                    isLoaded = result.status == 0
                    running = result.output.contains("state = running")
                } else if let state = loaded[label] {
                    isLoaded = true
                    running = state
                } else {
                    isLoaded = scope == .userAgent ? false : nil
                }
                let appURL = program.flatMap(Self.enclosingApp)
                let developer = appURL.flatMap(AppDiscovery.developer) ?? program.flatMap { AppDiscovery.developer(for: URL(filePath: $0)) }
                let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
                items.append(LaunchItem(plist: url, label: label, program: program, scope: scope,
                                        runAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive,
                                        disabledInPlist: plist["Disabled"] as? Bool ?? false,
                                        isLoaded: isLoaded, isRunning: running, appURL: appURL, developer: developer))
            }
        }
        return items.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func enclosingApp(_ path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(filePath: String(path[..<range.lowerBound]) + ".app")
    }

    /// Reads the classic "Open at Login" list through System Events. Requires the
    /// user's Automation consent; only invoked when the user asks.
    static func openAtLoginApps() async throws -> [OpenAtLoginApp] {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with i in login items
                set out to out & (name of i) & tab & (path of i) & linefeed
            end repeat
            return out
        end tell
        """
        let result = await Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            if result.error.contains("-1743") {
                throw TidyError.commandFailed("Allow access in System Settings > Privacy & Security > Automation.")
            }
            throw TidyError.commandFailed(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return OpenAtLoginApp(name: name, path: parts.count > 1 ? parts[1] : nil)
        }
    }

    // MARK: - Tidy's own login item

    @MainActor static var tidyLaunchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @MainActor static func setTidyLaunchesAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

// MARK: - Storage health

struct DiskHealth: Sendable {
    let smartStatus: String?
    let deviceName: String?
    let solidState: Bool?
    let fileSystem: String?
    let isEncrypted: Bool?
}

enum DiskHealthService {
    static func startupDisk() async -> DiskHealth {
        let result = await Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/"])
        guard result.status == 0, let data = result.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return DiskHealth(smartStatus: nil, deviceName: nil, solidState: nil, fileSystem: nil, isEncrypted: nil)
        }
        return DiskHealth(smartStatus: plist["SMARTStatus"] as? String,
                          deviceName: plist["MediaName"] as? String ?? plist["IORegistryEntryName"] as? String,
                          solidState: plist["SolidState"] as? Bool,
                          fileSystem: plist["FilesystemName"] as? String,
                          isEncrypted: plist["FileVault"] as? Bool ?? plist["Encryption"] as? Bool)
    }
}
