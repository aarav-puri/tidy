import Foundation
import Security

struct InstalledApp: Identifiable, Sendable, Hashable {
    var id: String { url.path(percentEncoded: false) }
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let isSystemApp: Bool
    let isAppStore: Bool
    var developer: String?
    var size: Int64?
    var lastUsed: Date?
    var relatedSize: Int64?

    /// Apps that macOS protects or that Tidy will not uninstall.
    var isProtected: Bool {
        isSystemApp || url.path(percentEncoded: false).hasPrefix("/System/") || bundleIdentifier == Bundle.main.bundleIdentifier
    }

    var protectionReason: String? {
        if bundleIdentifier == Bundle.main.bundleIdentifier { return "Tidy can't uninstall itself." }
        if isProtected { return "This app is part of macOS." }
        return nil
    }
}

enum AssociatedKind: String, Sendable, CaseIterable, Identifiable, Codable {
    case bundle, caches, preferences, supportFiles, containers, sharedData, savedState, logs, webData, launchAgents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bundle: "Application"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .supportFiles: "Application Support"
        case .containers: "Container"
        case .sharedData: "Shared Data"
        case .savedState: "Saved Window State"
        case .logs: "Logs"
        case .webData: "Web Data & Cookies"
        case .launchAgents: "Login & Background Items"
        }
    }

    var symbol: String {
        switch self {
        case .bundle: "app"
        case .caches: "shippingbox"
        case .preferences: "slider.horizontal.3"
        case .supportFiles: "folder"
        case .containers: "cube"
        case .sharedData: "person.2"
        case .savedState: "macwindow"
        case .logs: "doc.plaintext"
        case .webData: "globe"
        case .launchAgents: "power"
        }
    }

    var caution: String? {
        switch self {
        case .preferences: "Removes the app's settings."
        case .supportFiles: "May contain your data."
        case .containers: "May contain your documents."
        case .sharedData: "Shared with other apps."
        default: nil
        }
    }
}

struct AssociatedFile: Identifiable, Sendable, Hashable {
    var id: URL { url }
    let url: URL
    let kind: AssociatedKind
    let size: Int64
    /// How Tidy verified the relationship to the app.
    let evidence: String
    let risk: RiskLevel
    var isSelected: Bool
}

enum AppDiscoveryEvent: Sendable {
    case apps([InstalledApp])
    case update(InstalledApp)
    case finished
}

enum AppDiscovery {
    static var searchRoots: [(URL, Bool)] {
        [(URL(filePath: "/Applications"), false),
         (FileSystem.home.appending(path: "Applications"), false),
         (URL(filePath: "/System/Applications"), true)]
    }

    static func discover() -> AsyncStream<AppDiscoveryEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var apps: [InstalledApp] = []
                var seen = Set<String>()
                for (root, system) in searchRoots {
                    for link in findApps(in: root, depth: 0) {
                        // Some macOS apps appear in /Applications as symlinks into /System.
                        let url = FileSystem.info(link)?.isSymlink == true ? link.resolvingSymlinksInPath() : link
                        let isSystem = system || url.path(percentEncoded: false).hasPrefix("/System/")
                        let key = FileSystem.canonicalPath(url)
                        guard seen.insert(key).inserted, let app = makeApp(url, system: isSystem) else { continue }
                        apps.append(app)
                    }
                }
                apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                continuation.yield(.apps(apps))

                await withTaskGroup(of: InstalledApp?.self) { group in
                    var iterator = apps.makeIterator()
                    func addNext() -> Bool {
                        guard let app = iterator.next() else { return false }
                        group.addTask {
                            if Task.isCancelled { return nil }
                            var app = app
                            app.size = FileSystem.usage(of: app.url).bytes
                            app.developer = developer(for: app.url)
                            app.lastUsed = FileSystem.lastUsedDate(app.url)
                            return app
                        }
                        return true
                    }
                    for _ in 0..<4 { _ = addNext() }
                    for await app in group {
                        if let app { continuation.yield(.update(app)) }
                        if Task.isCancelled { group.cancelAll(); break }
                        _ = addNext()
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Bundle identifiers of every app in the standard application folders. Fast: reads Info.plist only.
    static func installedIdentifiers() -> Set<String> {
        var ids = Set<String>()
        for (root, _) in searchRoots {
            for url in findApps(in: root, depth: 0) {
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
            }
        }
        if let own = Bundle.main.bundleIdentifier { ids.insert(own) }
        return ids
    }

    static func findApps(in folder: URL, depth: Int) -> [URL] {
        guard depth < 3, let children = FileSystem.children(of: folder) else { return [] }
        var result: [URL] = []
        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            if child.pathExtension == "app" {
                result.append(child)
            } else if FileSystem.info(child)?.isDirectory == true, !Packages.isPackage(name) {
                result.append(contentsOf: findApps(in: child, depth: depth + 1))
            }
        }
        return result
    }

    static func makeApp(_ url: URL, system: Bool) -> InstalledApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let localized = bundle.localizedInfoDictionary ?? [:]
        _ = localized
        var name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        let version = short ?? build
        let isAppStore = FileSystem.exists(url.appending(path: "Contents/_MASReceipt/receipt"))
        return InstalledApp(url: url, name: name,
                            bundleIdentifier: bundle.bundleIdentifier, version: version,
                            isSystemApp: system, isAppStore: isAppStore)
    }

    /// Determines the developer from the code signature, falling back to the copyright string.
    static func developer(for url: URL) -> String? {
        var staticCode: SecStaticCode?
        if SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode {
            var info: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
               let dict = info as? [String: Any],
               let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
               let leaf = certificates.first,
               let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                if summary == "Software Signing" { return "Apple" }
                for prefix in ["Developer ID Application: ", "Apple Development: ", "Apple Distribution: ", "Mac Developer: "] where summary.hasPrefix(prefix) {
                    var name = String(summary.dropFirst(prefix.count))
                    if let paren = name.range(of: " (", options: .backwards) { name = String(name[..<paren.lowerBound]) }
                    return name
                }
            }
        }
        guard let copyright = Bundle(url: url)?.infoDictionary?["NSHumanReadableCopyright"] as? String else { return nil }
        return cleanCopyright(copyright)
    }

    private static func cleanCopyright(_ value: String) -> String? {
        var text = value.replacingOccurrences(of: "Copyright", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "©", with: "").replacingOccurrences(of: "(c)", with: "", options: .caseInsensitive)
        if let range = text.range(of: "All rights reserved", options: .caseInsensitive) { text = String(text[..<range.lowerBound]) }
        text = text.replacingOccurrences(of: #"\b(19|20)\d{2}(\s*[-–]\s*(19|20)\d{2})?\b"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.isEmpty || text.count > 60 ? nil : text
    }

    // MARK: - Associated files

    /// Finds files that belong to an app. Relationships are verified by the app's
    /// exact bundle identifier or team identifier. Name matches are reported
    /// separately at lower confidence and are never preselected.
    static func associatedFiles(for app: InstalledApp) async -> [AssociatedFile] {
        await Task.detached(priority: .userInitiated) {
            var results: [AssociatedFile] = []
            let lib = FileSystem.library
            if !app.isProtected {
                let size = app.size ?? FileSystem.usage(of: app.url).bytes
                results.append(AssociatedFile(url: app.url, kind: .bundle, size: size, evidence: "The application itself",
                                              risk: .recommended, isSelected: true))
            }
            guard let id = app.bundleIdentifier, !id.isEmpty else { return results }
            var seen = Set<String>()

            func add(_ url: URL, _ kind: AssociatedKind, evidence: String, risk: RiskLevel, selected: Bool) {
                guard FileSystem.exists(url), seen.insert(url.path(percentEncoded: false)).inserted else { return }
                let info = FileSystem.info(url)
                let size = info?.isDirectory == true ? FileSystem.usage(of: url).bytes : (info?.allocated ?? 0)
                results.append(AssociatedFile(url: url, kind: kind, size: size, evidence: evidence, risk: risk, isSelected: selected))
            }
            let exact = "Named with the app's identifier (\(id))"
            add(lib.appending(path: "Caches/\(id)"), .caches, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "HTTPStorages/\(id)"), .webData, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "HTTPStorages/\(id).binarycookies"), .webData, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "WebKit/\(id)"), .webData, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "Cookies/\(id).binarycookies"), .webData, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "Saved Application State/\(id).savedState"), .savedState, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "Logs/\(id)"), .logs, evidence: exact, risk: .recommended, selected: true)
            add(lib.appending(path: "Preferences/\(id).plist"), .preferences, evidence: exact, risk: .review, selected: true)
            add(lib.appending(path: "Application Support/\(id)"), .supportFiles, evidence: exact, risk: .review, selected: true)
            add(lib.appending(path: "Containers/\(id)"), .containers, evidence: exact, risk: .review, selected: true)
            add(lib.appending(path: "Application Scripts/\(id)"), .supportFiles, evidence: exact, risk: .recommended, selected: true)

            // Helpers named `<id>.<suffix>` are strongly related (e.g. `com.vendor.App.ShipIt`).
            for (folder, kind, risk) in [("Caches", AssociatedKind.caches, RiskLevel.recommended),
                                         ("Preferences", .preferences, .review),
                                         ("HTTPStorages", .webData, .recommended),
                                         ("Containers", .containers, .review)] {
                for child in FileSystem.children(of: lib.appending(path: folder)) ?? [] where child.lastPathComponent.hasPrefix(id + ".") {
                    let name = child.lastPathComponent
                    if folder == "Preferences", name == id + ".plist" { continue }
                    add(child, kind, evidence: "Named with the app's identifier as a prefix", risk: risk, selected: risk == .recommended)
                }
            }
            for child in FileSystem.children(of: lib.appending(path: "Preferences/ByHost")) ?? [] where child.lastPathComponent.hasPrefix(id + ".") {
                add(child, .preferences, evidence: exact, risk: .review, selected: true)
            }
            // Launch agents are verified by reading their Label.
            for child in FileSystem.children(of: lib.appending(path: "LaunchAgents")) ?? [] {
                guard let data = try? Data(contentsOf: child),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = plist["Label"] as? String, label == id || label.hasPrefix(id + ".") else { continue }
                add(child, .launchAgents, evidence: "Launch agent label matches the app's identifier", risk: .review, selected: true)
            }
            // Group containers are verified by the app's team identifier.
            if let team = teamIdentifier(for: app.url) {
                for child in FileSystem.children(of: lib.appending(path: "Group Containers")) ?? [] where child.lastPathComponent.hasPrefix(team + ".") {
                    add(child, .sharedData, evidence: "From the same developer. Other apps may use it.",
                        risk: .review, selected: false)
                }
            }
            // Name-only matches: plausible but unverified. Never preselected.
            let name = app.name
            if name.count >= 4 {
                for (folder, kind) in [("Application Support", AssociatedKind.supportFiles), ("Caches", .caches), ("Logs", .logs)] {
                    let url = lib.appending(path: "\(folder)/\(name)")
                    add(url, kind, evidence: "Same name as the app, but not verified.",
                        risk: .review, selected: false)
                }
            }
            return results
        }.value
    }

    static func teamIdentifier(for url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

// MARK: - Leftovers

struct LeftoverGroup: Identifiable, Sendable, Hashable {
    enum Confidence: Int, Sendable, Comparable {
        case medium = 1, high = 2
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        var title: String { self == .high ? "High" : "Medium" }
    }

    var id: String { identifier }
    let identifier: String
    let vendor: String
    let confidence: Confidence
    let explanation: String
    var items: [AssociatedFile]
    /// Used when the files can't be read from disk (demo content).
    var modifiedFallback: Date? = nil

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var lastModified: Date? { items.compactMap { FileSystem.info($0.url)?.modified }.max() ?? modifiedFallback }
}

/// Finds data left behind by apps that are no longer installed. Only items named
/// with a reverse-DNS identifier that no installed or registered app claims are
/// considered; anything Tidy can't attribute is left untouched.
struct LeftoverScanner: Sendable {
    let installedIdentifiers: Set<String>
    let runningIdentifiers: Set<String>
    let registeredCheck: @Sendable (String) -> Bool
    let includeContainers: Bool

    func scan() async -> [LeftoverGroup] {
        await Task.detached(priority: .userInitiated) {
            let lib = FileSystem.library
            var folders: [(String, AssociatedKind, String)] = [
                ("Caches", .caches, ""), ("Preferences", .preferences, ".plist"), ("Application Support", .supportFiles, ""),
                ("Saved Application State", .savedState, ".savedState"), ("HTTPStorages", .webData, ""),
                ("WebKit", .webData, ""), ("Logs", .logs, ""),
            ]
            if includeContainers { folders.append(("Containers", .containers, "")) }
            let installed = installedIdentifiers.union(runningIdentifiers).map { $0.lowercased() }
            let installedVendors = Set(installed.map(Self.vendor))
            var groups: [String: [AssociatedFile]] = [:]
            var displayID: [String: String] = [:]

            for (folder, kind, suffix) in folders {
                if Task.isCancelled { break }
                for child in FileSystem.children(of: lib.appending(path: folder)) ?? [] {
                    var name = child.lastPathComponent
                    if !suffix.isEmpty {
                        guard name.hasSuffix(suffix) else { continue }
                        name = String(name.dropLast(suffix.count))
                    } else if kind == .webData, name.hasSuffix(".binarycookies") {
                        name = String(name.dropLast(".binarycookies".count))
                    }
                    guard Self.isIdentifier(name) else { continue }
                    let lower = name.lowercased()
                    if Self.ignoredPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
                    // Owned by an installed app (exact, helper, or parent identifier)?
                    if installed.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }) { continue }
                    if registeredCheck(name) { continue }
                    let key = Self.groupKey(lower, installed: installed)
                    displayID[key] = displayID[key] ?? name
                    let info = FileSystem.info(child)
                    let size = info?.isDirectory == true ? FileSystem.usage(of: child).bytes : (info?.allocated ?? 0)
                    groups[key, default: []].append(AssociatedFile(url: child, kind: kind, size: size,
                                                                   evidence: "Named “\(child.lastPathComponent)”, and no installed app uses this identifier.",
                                                                   risk: .review, isSelected: false))
                }
            }
            return groups.compactMap { key, items -> LeftoverGroup? in
                let vendor = Self.vendor(key)
                let newest = items.compactMap { FileSystem.info($0.url)?.modified }.max() ?? .distantPast
                let stale = Date.now.timeIntervalSince(newest) > 30 * 86_400
                let vendorInstalled = installedVendors.contains(vendor)
                // App-only evidence: window state, sandbox containers, or WebKit data are created by
                // apps with a user interface, not by command-line tools or shared libraries.
                let kinds = Set(items.map(\.kind))
                let appEvidence = kinds.contains(.savedState) || kinds.contains(.containers)
                    || items.contains { $0.url.deletingLastPathComponent().lastPathComponent == "WebKit" } || kinds.count >= 3
                // Data from a developer whose other apps are installed is most likely shared with or
                // created by those apps (updaters, helpers). Without app-specific evidence it isn't listed.
                if vendorInstalled && !appEvidence { return nil }
                let confidence: LeftoverGroup.Confidence = !vendorInstalled && stale && appEvidence ? .high : .medium
                var explanation = "No installed app uses the identifier “\(displayID[key] ?? key)”."
                if vendorInstalled {
                    explanation += " Another app from the same developer is installed and might share this data."
                }
                if !stale {
                    explanation += " These files were modified recently, so something may still be using them."
                }
                if !appEvidence {
                    explanation += " The data could also come from a command-line tool or a helper rather than an app."
                }
                return LeftoverGroup(identifier: displayID[key] ?? key, vendor: vendor, confidence: confidence,
                                     explanation: explanation, items: items.sorted { $0.size > $1.size })
            }.sorted { ($0.confidence, $0.totalSize) > ($1.confidence, $1.totalSize) }
        }.value
    }

    /// Identifiers that belong to macOS, updaters, or third-party SDKs embedded in many apps.
    /// Data under these names can't be attributed to a single removed app, so it's never listed.
    static let ignoredPrefixes = [
        "com.apple.", "group.", "apple", "com.microsoft.autoupdate", "org.swift.", "com.google.keystone",
        "com.google.googleupdater", "com.google.firebase", "com.firebase.", "com.crashlytics", "io.fabric.",
        "com.amplitude.", "io.branch.", "com.segment.", "io.sentry", "com.mixpanel", "com.appsflyer", "com.braze",
        "com.facebook.sdk", "com.facebook.fbsdk", "com.bugsnag", "com.datadoghq", "com.microsoft.appcenter",
        "com.onesignal", "com.revenuecat", "com.launchdarkly", "io.intercom", "org.sparkle-project", "com.plausiblelabs",
        "com.squareup.", "com.getsentry", "com.newrelic", "com.instabug", "com.adjust.", "com.posthog", "com.statsig",
        "org.python.", "org.nodejs.", "com.github.electron", "com.electron.", "org.cups.", "com.google.gmp.",
    ]

    static func isIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = parts.first, tld.count >= 2, tld.count <= 6, tld.allSatisfy(\.isLetter) else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    static func vendor(_ identifier: String) -> String {
        identifier.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Groups helper identifiers (`com.vendor.app.helper`) under their app (`com.vendor.app`).
    static func groupKey(_ identifier: String, installed: [String]) -> String {
        let parts = identifier.split(separator: ".")
        return parts.prefix(3).joined(separator: ".")
    }
}
