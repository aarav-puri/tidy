import AppKit

enum Permissions {
    /// Full Disk Access is detected by attempting to read a file that macOS only
    /// exposes to apps with that permission. Nothing is read beyond the open check.
    static var hasFullDiskAccess: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            FileSystem.library.appending(path: "Safari/Bookmarks.plist").path(percentEncoded: false),
        ]
        for probe in probes {
            let fd = Darwin.open(probe, O_RDONLY)
            if fd >= 0 { Darwin.close(fd); return true }
        }
        return false
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }

    @MainActor
    static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    @MainActor
    static func openStorageSettings() {
        open("x-apple.systempreferences:com.apple.settings.Storage")
    }

    @MainActor
    static func openSoftwareUpdate() {
        open("x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
    }

    @MainActor
    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation")
    }

    @MainActor
    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    @MainActor
    static func openSystemApp(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

/// Runs short-lived system tools off the main thread.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    static func run(_ executable: String, _ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: executable)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch {
                    continuation.resume(returning: Result(status: -1, output: "", error: error.localizedDescription))
                    return
                }
                // Drain stdout before waiting so large outputs can't fill the pipe and deadlock.
                let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: Result(status: process.terminationStatus, output: o, error: e))
            }
        }
    }
}

enum TrashService {
    static let url = FileSystem.home.appending(path: ".Trash", directoryHint: .isDirectory)

    /// Size of the user's Trash, or nil when macOS doesn't allow Tidy to read it.
    static func measure() -> Int64? {
        guard FileSystem.isReadableDirectory(url) else { return nil }
        return FileSystem.usage(of: url).bytes
    }

    /// Asks Finder to empty the Trash, exactly as choosing Finder > Empty Trash would.
    static func emptyWithFinder() async throws {
        let result = await Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
        guard result.status == 0 else {
            if result.error.contains("-1743") {
                throw TidyError.commandFailed("Allow access in System Settings > Privacy & Security > Automation.")
            }
            throw TidyError.commandFailed("Finder couldn't empty the Trash. \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
