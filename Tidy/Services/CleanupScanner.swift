import Foundation

enum CleanupScanEvent: Sendable {
    case progress(Double, String)
    case category(CleanupCategoryResult)
}

/// Snapshot of app state the scanner needs, captured on the main actor before scanning.
struct RunningAppsSnapshot: Sendable {
    let bundleIdentifiers: Set<String>
    let names: Set<String>

    /// Whether a folder named `name` plausibly belongs to a running app, matched by
    /// bundle identifier, app name, or developer (for example "Google" while Chrome is open).
    func owns(_ name: String) -> Bool {
        let lower = name.lowercased()
        if names.contains(lower) || names.contains(where: { $0.hasPrefix(lower + " ") }) { return true }
        return bundleIdentifiers.contains { id in
            let id = id.lowercased()
            if lower == id || lower.hasPrefix(id + ".") || id.hasPrefix(lower + ".") { return true }
            // A plain folder named after the developer, e.g. "google" for com.google.Chrome.
            let parts = id.split(separator: ".")
            return !lower.contains(".") && parts.count >= 3 && parts[1] != "apple" && String(parts[1]) == lower
        }
    }
}

/// Finds cleanup candidates in well-understood user-level locations only.
/// Classification rules are deliberately conservative; see `classifyCache`.
struct CleanupScanner: Sendable {
    let running: RunningAppsSnapshot
    let excludedPaths: [String]
    let protectedPaths: [String]

    private var lib: URL { FileSystem.library }
    private let day: TimeInterval = 86_400

    func scan() -> AsyncStream<CleanupScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let kinds = CleanupCategoryKind.allCases
                for (index, kind) in kinds.enumerated() {
                    if Task.isCancelled { break }
                    let base = Double(index) / Double(kinds.count)
                    let span = 1.0 / Double(kinds.count)
                    continuation.yield(.progress(base, kind.scanningLabel))
                    let result = self.scan(kind) { fraction in
                        continuation.yield(.progress(base + span * fraction, kind.scanningLabel))
                    }
                    if Task.isCancelled { break }
                    continuation.yield(.category(result))
                }
                continuation.yield(.progress(1, "Finishing…"))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func scan(_ kind: CleanupCategoryKind, progress: (Double) -> Void) -> CleanupCategoryResult {
        switch kind {
        case .userCaches: scanCaches(progress: progress)
        case .logs: scanLogs()
        case .temporaryFiles: scanTemporary()
        case .partialDownloads: scanPartialDownloads()
        case .developer: scanDeveloper()
        case .deviceBackups: scanBackups()
        case .trash: scanTrash()
        }
    }

    // MARK: - Helpers

    private func isExcluded(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return excludedPaths.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    private func isUserProtected(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return protectedPaths.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    private func makeItem(_ url: URL, kind: CleanupCategoryKind, risk: RiskLevel, reason: String,
                          bundleID: String? = nil, usage precomputed: FileSystem.Usage? = nil) -> CleanupItem? {
        guard let info = FileSystem.info(url) else { return nil }
        let usage = precomputed ?? (info.isDirectory ? FileSystem.usage(of: url) : FileSystem.Usage(bytes: info.allocated, files: 1))
        guard usage.bytes > 0 else { return nil }
        var risk = risk, reason = reason
        if isUserProtected(url) {
            risk = .protected
            reason = "In your protected locations."
        } else if info.isSystemProtected {
            risk = .protected
            reason = "macOS protects this item with System Integrity Protection."
        } else if info.owner != getuid() {
            risk = .protected
            reason = "Belongs to another user or to macOS."
        }
        return CleanupItem(url: url, name: url.lastPathComponent, size: usage.bytes,
                           modified: usage.newestModification ?? info.modified, risk: risk, reason: reason,
                           category: kind, bundleIdentifier: bundleID, isSelected: risk == .recommended)
    }

    private static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    // MARK: - Caches

    /// Apple cache folders known to hold data that is costly or disruptive to rebuild.
    private static let sensitiveAppleCaches: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.containermanagerd",
        "com.apple.homed", "com.apple.HomeKit", "com.apple.findmy.fmipcore", "com.apple.icloud.fmfd",
        "com.apple.ap.adprivacyd", "com.apple.nsurlsessiond", "com.apple.passd", "com.apple.amsengagementd",
        "com.apple.Safari.SafeBrowsing", "com.apple.mediaanalysisd", "com.apple.photoanalysisd",
        "com.apple.Photos", "com.apple.iCloudHelper", "com.apple.cloudd", "com.apple.parsecd", "GeoServices",
    ]

    private func scanCaches(progress: (Double) -> Void) -> CleanupCategoryResult {
        let root = lib.appending(path: "Caches", directoryHint: .isDirectory)
        var result = CleanupCategoryResult(kind: .userCaches, items: [])
        guard let children = FileSystem.children(of: root) else {
            result.unavailable.append("~/Library/Caches couldn't be read.")
            return result
        }
        let ownID = Bundle.main.bundleIdentifier ?? ""
        for (index, url) in children.enumerated() {
            if Task.isCancelled { break }
            if index % 4 == 0 { progress(Double(index) / Double(max(children.count, 1))) }
            let name = url.lastPathComponent
            if name == ".DS_Store" || name == ownID || isExcluded(url) { continue }
            guard FileSystem.info(url)?.isDirectory == true else { continue }
            let usage = FileSystem.usage(of: url)
            let (risk, reason) = classifyCache(name: name, url: url, size: usage.bytes)
            if let item = makeItem(url, kind: .userCaches, risk: risk, reason: reason,
                                   bundleID: Self.looksLikeBundleID(name) ? name : nil, usage: usage) {
                result.items.append(item)
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    /// Caches written by developer tools that re-download their contents on demand.
    private static let toolCaches: Set<String> = [
        "homebrew", "pip", "node-gyp", "electron", "electron-builder", "ms-playwright", "ms-playwright-mcp", "yarn",
        "cocoapods", "go-build", "typescript", "pnpm", "deno", "cypress", "puppeteer", "bazel", "org.carthage.carthagekit",
        "org.swift.swiftpm", "pypoetry", "uv", "ruff", "prisma", "turbo", "next-swc",
    ]

    private func classifyCache(name: String, url: URL, size: Int64) -> (RiskLevel, String) {
        if !FileSystem.isReadableDirectory(url) {
            return (.protected, "macOS restricts access to this cache.")
        }
        if Self.sensitiveAppleCaches.contains(name) {
            return (.protected, "macOS uses this cache for iCloud, accounts, or system services. Removing it can disrupt syncing.")
        }
        if running.owns(name) {
            return (.review, "Used by an open app. Quit the app first.")
        }
        if name.hasPrefix("com.apple.") {
            return (.review, "Used by macOS. Some features may be slower until it's rebuilt.")
        }
        if Self.toolCaches.contains(name.lowercased()) {
            return (.recommended, "Developer tool downloads. Downloaded again when needed.")
        }
        if size > 1_000_000_000 {
            return (.review, "Large cache. May include offline content the app would download again.")
        }
        return (.recommended, "The app rebuilds this when needed.")
    }

    // MARK: - Logs

    private func scanLogs() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .logs, items: [])
        let root = lib.appending(path: "Logs", directoryHint: .isDirectory)
        guard let children = FileSystem.children(of: root) else {
            result.unavailable.append("~/Library/Logs couldn't be read.")
            return result
        }
        for url in children where !isExcluded(url) && url.lastPathComponent != ".DS_Store" {
            if Task.isCancelled { break }
            let name = url.lastPathComponent
            guard let info = FileSystem.info(url) else { continue }
            let risk: RiskLevel
            let reason: String
            if name == "DiagnosticReports" {
                risk = .review
                reason = "Crash reports. Keep them if you're troubleshooting."
            } else if running.owns(name) {
                risk = .review
                reason = "Logs for an app that's currently open."
            } else if Date.now.timeIntervalSince(info.modified) < day {
                risk = .review
                reason = "Updated today. May still be in use."
            } else {
                risk = .recommended
                reason = "Older logs. Apps create new ones as needed."
            }
            if let item = makeItem(url, kind: .logs, risk: risk, reason: reason) { result.items.append(item) }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    // MARK: - Temporary files

    private func scanTemporary() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .temporaryFiles, items: [])
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        guard let children = FileSystem.children(of: root) else {
            result.unavailable.append("Your temporary folder couldn't be read.")
            return result
        }
        let ownID = Bundle.main.bundleIdentifier ?? ""
        for url in children {
            if Task.isCancelled { break }
            let name = url.lastPathComponent
            if name.hasPrefix(ownID) || isExcluded(url) { continue }
            guard let info = FileSystem.info(url), info.owner == getuid() else { continue }
            let usage = info.isDirectory ? FileSystem.usage(of: url) : FileSystem.Usage(bytes: info.allocated, files: 1, newestModification: info.modified)
            // Age is judged by the newest file inside, so active folders are never listed.
            let newest = max(usage.newestModification ?? info.modified, info.modified)
            let age = Date.now.timeIntervalSince(newest)
            guard age > 3 * day else { continue }
            let risk: RiskLevel
            let reason: String
            if running.owns(name) {
                risk = .review
                reason = "Used by an open app."
            } else if name.hasPrefix("com.apple.") || name.hasPrefix("TemporaryItems") {
                risk = .review
                reason = "Created by macOS. Unused for \(Int(age / day)) days."
            } else if age > 7 * day {
                risk = .recommended
                reason = "Unused for \(Int(age / day)) days."
            } else {
                risk = .review
                reason = "Unused for \(Int(age / day)) days. May still be needed."
            }
            if let item = makeItem(url, kind: .temporaryFiles, risk: risk, reason: reason, usage: usage) {
                result.items.append(item)
            }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    // MARK: - Unfinished downloads

    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "aria2"]

    private func scanPartialDownloads() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .partialDownloads, items: [])
        let root = FileSystem.home.appending(path: "Downloads", directoryHint: .isDirectory)
        guard let children = FileSystem.children(of: root) else {
            result.unavailable.append("No access to your Downloads folder.")
            return result
        }
        for url in children where Self.partialExtensions.contains(url.pathExtension.lowercased()) && !isExcluded(url) {
            guard let info = FileSystem.info(url) else { continue }
            let age = Date.now.timeIntervalSince(info.modified)
            let risk: RiskLevel = age > day ? .recommended : .review
            let reason = age > day
                ? "Incomplete since \(Format.relative(info.modified))."
                : "May still be downloading."
            if let item = makeItem(url, kind: .partialDownloads, risk: risk, reason: reason) { result.items.append(item) }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    // MARK: - Developer

    private func scanDeveloper() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .developer, items: [])
        let dev = lib.appending(path: "Developer", directoryHint: .isDirectory)
        let xcodeRunning = running.bundleIdentifiers.contains("com.apple.dt.Xcode")
        let derivedData = dev.appending(path: "Xcode/DerivedData", directoryHint: .isDirectory)
        if let projects = FileSystem.children(of: derivedData) {
            for url in projects where FileSystem.info(url)?.isDirectory == true && !isExcluded(url) {
                if Task.isCancelled { break }
                let risk: RiskLevel = xcodeRunning ? .review : .recommended
                let reason = xcodeRunning
                    ? "Xcode is open. Quit it first."
                    : "Xcode rebuilds this the next time you build."
                if let item = makeItem(url, kind: .developer, risk: risk, reason: reason) { result.items.append(item) }
            }
        }
        let fixed: [(String, RiskLevel, String)] = [
            ("Xcode/iOS DeviceSupport", .review, "Copied again when you reconnect a device."),
            ("Xcode/watchOS DeviceSupport", .review, "Copied again when needed."),
            ("Xcode/Archives", .review, "Needed to read crash reports or resubmit a build."),
            ("CoreSimulator/Caches", .recommended, "Rebuilt automatically."),
        ]
        for (relative, risk, reason) in fixed {
            if Task.isCancelled { break }
            let url = dev.appending(path: relative, directoryHint: .isDirectory)
            guard FileSystem.exists(url), !isExcluded(url) else { continue }
            if let item = makeItem(url, kind: .developer, risk: risk, reason: reason) { result.items.append(item) }
        }
        let home = FileSystem.home
        let toolCaches: [(URL, String)] = [
            (home.appending(path: ".npm/_cacache"), "npm downloads packages again when needed."),
            (home.appending(path: ".cache/yarn"), "Yarn downloads packages again when needed."),
            (home.appending(path: "Library/pnpm/store"), "Projects may need to reinstall packages."),
        ]
        for (url, reason) in toolCaches where FileSystem.exists(url) && !isExcluded(url) {
            if let item = makeItem(url, kind: .developer, risk: .recommended, reason: reason) { result.items.append(item) }
        }
        result.items.sort { $0.size > $1.size }
        return result
    }

    // MARK: - Backups

    private func scanBackups() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .deviceBackups, items: [])
        let root = lib.appending(path: "Application Support/MobileSync/Backup", directoryHint: .isDirectory)
        guard FileSystem.exists(root) else { return result }
        guard let backups = FileSystem.children(of: root) else {
            result.unavailable.append("iPhone and iPad backups require Full Disk Access to measure.")
            return result
        }
        for url in backups where FileSystem.info(url)?.isDirectory == true {
            if Task.isCancelled { break }
            var name = url.lastPathComponent
            if let data = try? Data(contentsOf: url.appending(path: "Info.plist")),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let device = plist["Device Name"] as? String {
                name = device
            }
            if var item = makeItem(url, kind: .deviceBackups, risk: .review,
                                   reason: "Backup of “\(name)”. Make sure you have a newer one first.") {
                item.isSelected = false
                result.items.append(item)
            }
        }
        return result
    }

    // MARK: - Trash

    private func scanTrash() -> CleanupCategoryResult {
        var result = CleanupCategoryResult(kind: .trash, items: [])
        guard let size = TrashService.measure() else {
            result.unavailable.append("Measuring the Trash requires Full Disk Access.")
            return result
        }
        guard size > 0 else { return result }
        result.items.append(CleanupItem(url: TrashService.url, name: "Trash", size: size, modified: nil, risk: .review,
                                        reason: "Emptying the Trash can't be undone.",
                                        category: .trash, isSelected: false))
        return result
    }
}
