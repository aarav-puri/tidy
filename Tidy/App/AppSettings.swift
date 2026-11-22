import SwiftUI
import Observation

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum ScanReminder: String, CaseIterable, Identifiable {
    case never, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: "Never"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var removalMode: RemovalMode { didSet { defaults.set(removalMode.rawValue, forKey: "removalMode") } }
    var confirmMoveToTrash: Bool { didSet { defaults.set(confirmMoveToTrash, forKey: "confirmMoveToTrash") } }
    var showMenuBarExtra: Bool { didSet { defaults.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var appearance: AppearancePreference { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var notifyWhenScansFinish: Bool { didSet { defaults.set(notifyWhenScansFinish, forKey: "notifyWhenScansFinish") } }
    var scanReminder: ScanReminder { didSet { defaults.set(scanReminder.rawValue, forKey: "scanReminder") } }
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: "keepHistory") } }
    var scanLocations: [String] { didSet { defaults.set(scanLocations, forKey: "scanLocations") } }
    var excludedPaths: [String] { didSet { defaults.set(excludedPaths, forKey: "excludedPaths") } }
    var protectedPaths: [String] { didSet { defaults.set(protectedPaths, forKey: "protectedPaths") } }
    /// Minimum size, in megabytes, for the Large & Old Files scan.
    var largeFileMinimumMB: Int { didSet { defaults.set(largeFileMinimumMB, forKey: "largeFileMinimumMB") } }
    /// Minimum size, in megabytes, for files considered by the duplicate finder.
    var duplicateMinimumMB: Int { didSet { defaults.set(duplicateMinimumMB, forKey: "duplicateMinimumMB") } }

    init() {
        let d = UserDefaults.standard
        removalMode = RemovalMode(rawValue: d.string(forKey: "removalMode") ?? "") ?? .moveToTrash
        confirmMoveToTrash = d.object(forKey: "confirmMoveToTrash") as? Bool ?? true
        showMenuBarExtra = d.object(forKey: "showMenuBarExtra") as? Bool ?? false
        appearance = AppearancePreference(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        notifyWhenScansFinish = d.object(forKey: "notifyWhenScansFinish") as? Bool ?? false
        scanReminder = ScanReminder(rawValue: d.string(forKey: "scanReminder") ?? "") ?? .never
        keepHistory = d.object(forKey: "keepHistory") as? Bool ?? true
        scanLocations = d.stringArray(forKey: "scanLocations") ?? [FileSystem.home.path(percentEncoded: false)]
        excludedPaths = d.stringArray(forKey: "excludedPaths") ?? []
        protectedPaths = d.stringArray(forKey: "protectedPaths") ?? []
        largeFileMinimumMB = d.object(forKey: "largeFileMinimumMB") as? Int ?? 100
        duplicateMinimumMB = d.object(forKey: "duplicateMinimumMB") as? Int ?? 1
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var scanRoots: [URL] {
        let roots = scanLocations.map { URL(filePath: $0, directoryHint: .isDirectory) }.filter(FileSystem.exists)
        return roots.isEmpty ? [FileSystem.home] : roots
    }

    func walker(minimumBytes: Int64) -> FileWalker {
        FileWalker(roots: scanRoots, excluded: Set(excludedPaths), minimumSize: minimumBytes)
    }
}
