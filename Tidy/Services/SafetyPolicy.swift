import Foundation

/// The single authority on whether Tidy may remove an item. Every removal path
/// in the app goes through `FileRemover`, which consults this policy immediately
/// before acting, regardless of how the item was classified during scanning.
struct SafetyPolicy: Sendable {
    enum Verdict: Sendable, Equatable {
        case allowed
        case denied(String)

        var reason: String? { if case .denied(let r) = self { r } else { nil } }
    }

    /// Paths that may contain removable items, but which themselves must never be removed.
    private let structural: Set<String>
    private let systemPrefixes: [String]
    private let userProtected: [String]
    private let ownBundle: String
    private let home: String

    init(userProtectedPaths: [String]) {
        let home = FileSystem.canonicalPath(FileSystem.home)
        self.home = home
        let lib = home + "/Library"
        var structural: Set<String> = ["/", "/Applications", "/Users", "/Volumes", "/private", "/private/var",
                                       "/private/tmp", "/private/var/folders", "/var", "/tmp", home]
        for name in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
                     "Library", ".Trash", "Developer", ".ssh", ".gnupg", ".config"] {
            structural.insert(home + "/" + name)
        }
        for name in ["Caches", "Logs", "Preferences", "Application Support", "Containers", "Group Containers",
                     "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "LaunchAgents", "Mobile Documents",
                     "CloudStorage", "Developer", "Developer/Xcode", "Keychains", "Mail", "Messages", "Safari",
                     "Application Scripts", "Fonts", "Calendars", "Accounts", "Photos"] {
            structural.insert(lib + "/" + name)
        }
        let tmp = FileSystem.canonicalPath(URL(filePath: NSTemporaryDirectory()))
        structural.insert(tmp)
        structural.insert(URL(filePath: tmp).deletingLastPathComponent().path(percentEncoded: false))
        self.structural = structural
        self.systemPrefixes = ["/System", "/bin", "/sbin", "/usr", "/private/etc", "/private/var/db",
                               "/private/var/root", "/private/var/vm", "/Library", "/dev", "/cores", "/opt",
                               "/private/var/log", "/Network", lib + "/Keychains", lib + "/Mail",
                               lib + "/Messages", lib + "/Accounts", lib + "/Calendars", lib + "/Biome",
                               lib + "/Sharing", lib + "/Mobile Documents/com~apple~CloudDocs/.Trash"]
        self.userProtected = userProtectedPaths.map { FileSystem.canonicalPath(URL(filePath: $0)) }
        self.ownBundle = FileSystem.canonicalPath(Bundle.main.bundleURL)
    }

    func evaluate(_ url: URL, allowApplicationBundles: Bool = false) -> Verdict {
        let path = FileSystem.canonicalPath(url)
        guard let info = FileSystem.info(url) else { return .denied("The item no longer exists.") }
        if structural.contains(path) {
            return .denied("This folder is required by your Mac.")
        }
        if path == ownBundle || path.hasPrefix(ownBundle + "/") {
            return .denied("This is part of Tidy.")
        }
        for prefix in systemPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return .denied("This location is protected by macOS.")
        }
        for prefix in userProtected where path == prefix || path.hasPrefix(prefix + "/") {
            return .denied("In your protected locations.")
        }
        if info.isSystemProtected {
            return .denied("This item is protected by macOS.")
        }
        if path.hasPrefix("/Applications/") {
            guard allowApplicationBundles else {
                return .denied("Use App Manager to remove apps.")
            }
            guard url.pathExtension == "app" else {
                return .denied("Only application bundles can be removed from the Applications folder.")
            }
        }
        // Must live somewhere the user owns: their home, /Applications (apps only), temp, or an external volume.
        let tmpRoot = FileSystem.canonicalPath(URL(filePath: NSTemporaryDirectory()))
        let permittedRoots = [home + "/", "/Applications/", tmpRoot + "/", "/Volumes/"]
        guard permittedRoots.contains(where: { path.hasPrefix($0) }) else {
            return .denied("This location can't be changed.")
        }
        return .allowed
    }

    /// Non-blocking cautions shown before removal.
    func warnings(for url: URL) -> [String] {
        let path = FileSystem.canonicalPath(url)
        var result: [String] = []
        if path.hasPrefix(home + "/Library/Mobile Documents/") {
            result.append("Removing it from iCloud Drive removes it from all your devices.")
        }
        if path.hasPrefix(home + "/Library/CloudStorage/") {
            result.append("This item is in a cloud storage folder and may be removed from the cloud as well.")
        }
        return result
    }
}
