#if DEBUG
import Foundation

/// Realistic, invented content for screenshots and marketing material.
/// Launch with `-TidyDemo YES`. Nothing here touches the disk: demo mode never
/// scans, never removes, and never writes Activity History.
enum DemoData {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "TidyDemo") }

    // MARK: - Helpers

    static let home = FileSystem.home
    static let library = home.appending(path: "Library")
    static func h(_ path: String) -> URL { home.appending(path: path) }
    static func lib(_ path: String) -> URL { library.appending(path: path) }
    static func days(_ n: Double) -> Date { .now.addingTimeInterval(-n * 86_400) }
    static let GB: Int64 = 1_000_000_000
    static let MB: Int64 = 1_000_000
    static func gb(_ v: Double) -> Int64 { Int64(v * 1_000_000_000) }
    static func mb(_ v: Double) -> Int64 { Int64(v * 1_000_000) }

    // MARK: - Mac and volume

    static let macInfo = MacInfo(
        modelName: "MacBook Pro (14-inch, M4 Pro, 2024)",
        modelIdentifier: "Mac16,8",
        serialNumber: "K7XQ2MV9PL",
        osVersion: "macOS 26.1",
        osBuild: "25B78",
        processor: "Apple M4 Pro",
        coreSummary: "12 cores (8 performance, 4 efficiency)",
        coreCount: "12 Cores",
        coreDetail: "8 Performance · 4 Efficiency",
        memory: 24 * 1_073_741_824,
        computerName: "Alex's MacBook Pro"
    )

    static let volume = VolumeInfo(name: "Macintosh HD", total: gb(994.66), available: gb(312.4), free: gb(298.1), format: "APFS")

    static var categories: [StorageCategory] {
        let measured: [(StorageCategory.Kind, Double)] = [
            (.applications, 38.2), (.documents, 96.5), (.photos, 142.8), (.downloads, 21.4), (.developer, 64.7), (.library, 118.3),
        ]
        var list = measured.map { StorageCategory(kind: $0.0, bytes: gb($0.1), isEstimate: false, isPartial: false) }
        let sum = list.reduce(0) { $0 + $1.bytes }
        list.append(StorageCategory(kind: .systemAndOther, bytes: volume.used - sum, isEstimate: true, isPartial: false))
        return list
    }

    // MARK: - Smart Cleanup

    static var cleanupCategories: [CleanupCategoryResult] {
        func item(_ url: URL, _ name: String, _ size: Int64, _ age: Double, _ risk: RiskLevel, _ reason: String,
                  _ kind: CleanupCategoryKind, bundle: String? = nil) -> CleanupItem {
            CleanupItem(url: url, name: name, size: size, modified: days(age), risk: risk, reason: reason, category: kind,
                        bundleIdentifier: bundle, isSelected: risk == .recommended)
        }
        let cacheReason = "Cache data. The app rebuilds it automatically."
        let caches: [CleanupItem] = [
            item(lib("Caches/com.spotify.client"), "Spotify", gb(3.42), 1, .recommended, cacheReason, .userCaches, bundle: "com.spotify.client"),
            item(lib("Caches/Google/Chrome"), "Google Chrome", gb(2.18), 0.2, .recommended, cacheReason, .userCaches, bundle: "com.google.Chrome"),
            item(lib("Caches/com.figma.Desktop"), "Figma", gb(1.36), 2, .recommended, cacheReason, .userCaches, bundle: "com.figma.Desktop"),
            item(lib("Caches/com.tinyspeck.slackmacgap"), "Slack", mb(884), 0.5, .recommended, cacheReason, .userCaches, bundle: "com.tinyspeck.slackmacgap"),
            item(lib("Caches/com.microsoft.VSCode.ShipIt"), "Visual Studio Code Updates", mb(612), 9, .recommended, "Downloaded updates that were already installed.", .userCaches),
            item(lib("Caches/us.zoom.xos"), "zoom.us", mb(347), 4, .recommended, cacheReason, .userCaches, bundle: "us.zoom.xos"),
            item(lib("Caches/com.apple.Music"), "Music", mb(296), 3, .review, "Includes downloaded artwork. Music may redownload it.", .userCaches),
        ]
        let logs: [CleanupItem] = [
            item(lib("Logs/DiagnosticReports"), "Diagnostic Reports", mb(214), 6, .recommended, "Crash and hang reports. Only useful for troubleshooting.", .logs),
            item(lib("Logs/JetBrains"), "JetBrains", mb(148), 12, .recommended, "Activity logs from JetBrains IDEs.", .logs),
            item(lib("Logs/zoom.us"), "zoom.us", mb(36), 4, .recommended, "Activity logs from zoom.us.", .logs),
        ]
        let temp: [CleanupItem] = [
            item(URL(filePath: "/private/var/folders/demo/T/com.apple.Photos.export"), "Photos Export", gb(1.12), 18, .recommended, "Temporary export files not used in 18 days.", .temporaryFiles),
            item(URL(filePath: "/private/var/folders/demo/T/ffmpeg-render"), "Render Scratch", mb(468), 11, .review, "Large temporary files. Make sure no render is in progress.", .temporaryFiles),
        ]
        let partial: [CleanupItem] = [
            item(h("Downloads/macOS-Installer.dmg.download"), "macOS-Installer.dmg.download", gb(2.04), 26, .recommended, "Download stopped 26 days ago and can't be opened.", .partialDownloads),
            item(h("Downloads/Blender-4.3.crdownload"), "Blender-4.3.crdownload", mb(188), 40, .recommended, "Download stopped 40 days ago and can't be opened.", .partialDownloads),
        ]
        let developer: [CleanupItem] = [
            item(lib("Developer/Xcode/DerivedData"), "Xcode Derived Data", gb(14.6), 2, .recommended, "Build products Xcode recreates on the next build.", .developer),
            item(lib("Developer/CoreSimulator/Caches"), "Simulator Caches", gb(4.81), 7, .recommended, "Simulator caches rebuilt when needed.", .developer),
            item(h(".npm/_cacache"), "npm Cache", gb(2.26), 1, .recommended, "Package cache. npm downloads packages again when needed.", .developer),
            item(lib("Developer/Xcode/iOS DeviceSupport/18.2"), "iOS 18.2 Device Support", gb(3.9), 94, .review, "Debug symbols for an iOS version. Keep if you still test on it.", .developer),
        ]
        let backups: [CleanupItem] = [
            item(lib("Application Support/MobileSync/Backup/00008110-demo"), "Alex's iPhone (March)", gb(28.4), 238, .review, "An older iPhone backup. Make sure you have a newer one first.", .deviceBackups),
        ]
        let protected: [CleanupItem] = [
            item(lib("Caches/CloudKit"), "CloudKit", mb(512), 0.1, .protected, "Used by iCloud sync. Never removed.", .userCaches),
            item(lib("Caches/com.apple.Safari"), "Safari", mb(244), 0.1, .protected, "Safari is running.", .userCaches),
        ]
        return [
            CleanupCategoryResult(kind: .userCaches, items: caches, protectedItems: protected),
            CleanupCategoryResult(kind: .logs, items: logs),
            CleanupCategoryResult(kind: .temporaryFiles, items: temp),
            CleanupCategoryResult(kind: .partialDownloads, items: partial),
            CleanupCategoryResult(kind: .developer, items: developer),
            CleanupCategoryResult(kind: .deviceBackups, items: backups),
        ]
    }

    // MARK: - Storage Explorer

    static var storageTree: StorageNode {
        func dir(_ path: String, _ size: Double, _ count: Int, _ age: Double) -> StorageNode {
            StorageNode(name: (path as NSString).lastPathComponent, url: h(path), isDirectory: true, size: gb(size), itemCount: count, modified: days(age))
        }
        let children: [StorageNode] = [
            dir("Pictures", 142.8, 48_210, 1),
            dir("Library", 118.3, 412_904, 0),
            dir("Documents", 74.2, 36_118, 0.3),
            dir("Developer", 52.6, 284_015, 0.1),
            dir("Movies", 38.9, 412, 6),
            dir("Desktop", 22.3, 1_204, 0.2),
            dir("Downloads", 21.4, 356, 0.4),
            dir("Music", 12.7, 3_480, 21),
            dir(".npm", 4.1, 91_244, 1),
            dir("Creative Cloud Files", 3.6, 812, 14),
            dir(".docker", 2.9, 1_022, 3),
            dir("Public", 0.42, 12, 210),
            StorageNode(name: "184 smaller items", url: home, isDirectory: false, size: gb(1.31), itemCount: 184, modified: nil, isAggregate: true),
        ]
        let total = children.reduce(0) { $0 + $1.size }
        return StorageNode(name: "Alex", url: home, isDirectory: true, size: total,
                           itemCount: children.reduce(0) { $0 + $1.itemCount }, modified: .now, children: children)
    }

    // MARK: - Large files

    static var largeFiles: [FoundFile] {
        var inode: UInt64 = 1_000
        func file(_ path: String, _ size: Int64, _ modified: Double, _ opened: Double?, _ kind: FileKind) -> FoundFile {
            inode += 1
            return FoundFile(url: h(path), size: size, modified: days(modified), kind: kind, device: 1, inode: inode,
                             lastOpened: opened.map(days))
        }
        return [
            file("Movies/Iceland Trip 4K Master.mov", gb(18.4), 420, 400, .video),
            file("Developer/Images/ubuntu-24.04-arm64.iso", gb(6.2), 300, 280, .diskImage),
            file("Movies/Wedding Highlights Raw.mp4", gb(5.7), 610, 590, .video),
            file("Documents/Archive/Photo Library Export 2023.zip", gb(4.9), 700, 690, .archive),
            file("Downloads/Xcode_16.2.xip", gb(3.1), 160, 158, .archive),
            file("Movies/Screen Recordings/Keynote Rehearsal.mov", gb(2.8), 95, 90, .video),
            file("Documents/Projects/Brand Film/Brand Film v12.prproj", gb(1.9), 40, 12, .document),
            file("Music/Logic/Album Sessions.logicx.zip", gb(1.6), 520, 510, .archive),
            file("Downloads/Windows11_ARM.vhdx", gb(1.4), 380, 370, .diskImage),
            file("Desktop/Conference Talk.key", mb(986), 30, 8, .document),
            file("Pictures/Panorama Stitch.psb", mb(842), 260, 250, .image),
            file("Documents/Research/Survey Recordings.m4a", mb(612), 450, 440, .audio),
        ]
    }

    // MARK: - Duplicates

    static var duplicateGroups: [DuplicateGroup] {
        var inode: UInt64 = 5_000
        func group(_ name: String, _ size: Int64, _ kind: FileKind, _ folders: [(String, Double)]) -> DuplicateGroup {
            DuplicateGroup(id: name, size: size, kind: kind, files: folders.map { folder, age in
                inode += 1
                return FoundFile(url: h("\(folder)/\(name)"), size: size, modified: days(age), kind: kind, device: 1, inode: inode)
            })
        }
        return [
            group("Product Launch Final.mp4", gb(1.24), .video, [("Movies/Exports", 64), ("Desktop", 63), ("Downloads", 61)]),
            group("Lightroom Catalog Backup.zip", mb(812), .archive, [("Documents/Backups", 120), ("Downloads", 118)]),
            group("Design System v3.fig", mb(286), .document, [("Documents/Design", 30), ("Desktop/Old Desktop", 29)]),
            group("IMG_4821.HEIC", mb(9.6), .image, [("Pictures/Imports/2024-08", 410), ("Desktop", 405), ("Downloads", 404)]),
            group("Quarterly Report Q3.pdf", mb(14.2), .document, [("Documents/Work", 55), ("Downloads", 55)]),
            group("Podcast Episode 12.wav", mb(146), .audio, [("Music/Podcast", 88), ("Documents/Podcast", 87)]),
            group("Floor Plan.pdf", mb(6.8), .document, [("Documents/Home", 200), ("Downloads", 201), ("Desktop", 199)]),
        ].sorted { $0.wastedSpace > $1.wastedSpace }
    }

    // MARK: - Downloads

    static var downloads: [DownloadItem] {
        func item(_ name: String, _ size: Int64, _ age: Double, _ kind: FileKind, _ desc: String, _ source: String?, folder: Bool = false) -> DownloadItem {
            DownloadItem(url: h("Downloads/\(name)"), size: size, isFolder: folder, added: days(age), modified: days(age),
                         kind: kind, kindDescription: desc, source: source)
        }
        return [
            item("Xcode_16.2.xip", gb(3.1), 160, .archive, "XIP Archive", "developer.apple.com"),
            item("Figma-125.1.dmg", mb(212), 74, .diskImage, "Disk Image", "figma.com"),
            item("Docker.dmg", mb(586), 92, .diskImage, "Disk Image", "docker.com"),
            item("Zoom.pkg", mb(118), 140, .installer, "Installer Package", "zoom.us"),
            item("Brand Assets 2025.zip", mb(944), 21, .archive, "ZIP Archive", "drive.google.com"),
            item("Lecture 14 - Recording.mp4", gb(1.38), 9, .video, "MPEG-4 Movie", "canvas.instructure.com"),
            item("Tax Return 2024.pdf", mb(3.2), 210, .document, "PDF Document", "mail.google.com"),
            item("Team Offsite Photos", mb(764), 33, .image, "Folder", nil, folder: true),
            item("Wallpaper Pack.zip", mb(128), 380, .archive, "ZIP Archive", "unsplash.com"),
            item("Sample Track Stems.zip", mb(402), 260, .archive, "ZIP Archive", "splice.com"),
            item("Invoice-2048.pdf", mb(0.4), 4, .document, "PDF Document", "stripe.com"),
        ]
    }

    // MARK: - Apps

    /// Uses apps installed on this Mac only for their icons; every other value is invented.
    static var apps: [InstalledApp] {
        func app(_ file: String, _ name: String, _ id: String, _ version: String, _ dev: String?, _ size: Int64, _ used: Double?, store: Bool = false) -> InstalledApp {
            InstalledApp(url: URL(filePath: "/Applications/\(file)"), name: name, bundleIdentifier: id, version: version,
                         isSystemApp: false, isAppStore: store, developer: dev, size: size, lastUsed: used.map(days))
        }
        return [
            app("Xcode.app", "Xcode", "com.apple.dt.Xcode", "16.2", "Apple Inc.", gb(11.8), 1, store: true),
            app("Blender.app", "Blender", "org.blenderfoundation.blender", "4.3.2", "Stichting Blender Foundation", mb(986), 64),
            app("Google Chrome.app", "Google Chrome", "com.google.Chrome", "131.0.6778", "Google LLC", mb(1_420), 0.1),
            app("GitHub Desktop.app", "GitHub Desktop", "com.github.GitHubClient", "3.4.12", "GitHub", mb(702), 5),
            app("Microsoft PowerPoint.app", "Microsoft PowerPoint", "com.microsoft.Powerpoint", "16.92", "Microsoft Corporation", gb(2.1), 38, store: true),
            app("Microsoft Word.app", "Microsoft Word", "com.microsoft.Word", "16.92", "Microsoft Corporation", gb(2.6), 2, store: true),
            app("Notion.app", "Notion", "notion.id", "4.2.0", "Notion Labs, Incorporated", mb(268), 0.3),
            app("Notion Calendar.app", "Notion Calendar", "com.cron.electron", "1.128.0", "Notion Labs, Incorporated", mb(341), 0.5),
            app("OBS.app", "OBS", "com.obsproject.obs-studio", "31.0.1", "OBS Project", mb(512), 120),
            app("Opera.app", "Opera", "com.operasoftware.Opera", "115.0", "Opera Norway AS", mb(624), 240),
            app("Raspberry Pi Imager.app", "Raspberry Pi Imager", "org.raspberrypi.imagingutility", "1.9.0", "Raspberry Pi Ltd", mb(164), 300),
            app("Spotify.app", "Spotify", "com.spotify.client", "1.2.52", "Spotify AB", mb(398), 0.05),
            app("Tailscale.app", "Tailscale", "io.tailscale.ipn.macos", "1.78.1", "Tailscale Inc.", mb(96), 3, store: true),
            app("Visual Studio Code.app", "Visual Studio Code", "com.microsoft.VSCode", "1.96.2", "Microsoft Corporation", mb(612), 0.2),
            app("zoom.us.app", "zoom.us", "us.zoom.xos", "6.3.1", "Zoom Video Communications, Inc.", mb(434), 7),
        ]
    }

    // MARK: - Leftovers

    static var leftovers: [LeftoverGroup] {
        func file(_ path: String, _ kind: AssociatedKind, _ size: Int64) -> AssociatedFile {
            AssociatedFile(url: lib(path), kind: kind, size: size, evidence: "Named with the app's identifier", risk: .recommended, isSelected: false)
        }
        var age = 12.0
        func group(_ id: String, _ vendor: String, _ confidence: LeftoverGroup.Confidence, _ items: [AssociatedFile]) -> LeftoverGroup {
            age += 37
            return LeftoverGroup(identifier: id, vendor: vendor, confidence: confidence,
                                 explanation: confidence == .high ? "No installed app uses this identifier, and the app's files were removed."
                                                                  : "No installed app uses this identifier.",
                                 items: items, modifiedFallback: days(age))
        }
        return [
            group("com.adobe.Lightroom", "Adobe", .high, [
                file("Application Support/com.adobe.Lightroom", .supportFiles, gb(1.84)),
                file("Caches/com.adobe.Lightroom", .caches, mb(612)),
                file("Preferences/com.adobe.Lightroom.plist", .preferences, 48_000),
            ]),
            group("com.hnc.Discord", "Discord", .high, [
                file("Application Support/discord", .supportFiles, mb(742)),
                file("Caches/com.hnc.Discord", .caches, mb(218)),
                file("Saved Application State/com.hnc.Discord.savedState", .savedState, 96_000),
            ]),
            group("com.microsoft.teams2", "Microsoft", .high, [
                file("Containers/com.microsoft.teams2", .containers, mb(520)),
                file("Logs/com.microsoft.teams2", .logs, mb(44)),
            ]),
            group("com.electron.whatsapp", "WhatsApp", .medium, [
                file("Application Support/WhatsApp", .supportFiles, mb(388)),
            ]),
            group("com.getdropbox.dropbox", "Dropbox", .medium, [
                file("Application Support/Dropbox", .supportFiles, mb(126)),
                file("Preferences/com.getdropbox.dropbox.plist", .preferences, 12_000),
            ]),
            group("com.unity3d.UnityEditor5.x", "Unity", .medium, [
                file("Caches/com.unity3d.UnityEditor", .caches, mb(1_210)),
            ]),
        ]
    }

    // MARK: - Activity History

    static var history: [HistoryEntry] {
        func entry(_ age: Double, _ kind: ActivityKind, _ mode: RemovalMode, _ bytes: Int64, _ count: Int, _ detail: String) -> HistoryEntry {
            let items = (0..<count).map { i in
                RemovedItem(originalPath: lib("Caches/demo-\(kind.rawValue)-\(i)").path(percentEncoded: false),
                            trashedPath: mode == .moveToTrash ? h(".Trash/demo-\(i)").path(percentEncoded: false) : nil,
                            size: bytes / Int64(max(count, 1)))
            }
            return HistoryEntry(id: UUID(), date: days(age), kind: kind, mode: mode, bytes: bytes, items: items, failureCount: 0, detail: detail)
        }
        return [
            entry(0.08, .smartCleanup, .moveToTrash, gb(21.6), 48, "Smart Cleanup"),
            entry(1.3, .duplicates, .moveToTrash, gb(1.24), 2, "Duplicate Files"),
            entry(3.6, .uninstall, .moveToTrash, gb(2.7), 6, "Uninstall Final Cut Trial"),
            entry(6.2, .largeFiles, .moveToTrash, gb(9.8), 3, "Large & Old Files"),
            entry(9.0, .emptyTrash, .deleteImmediately, gb(18.3), 0, "Emptied the Trash"),
            entry(14.5, .leftovers, .moveToTrash, mb(842), 9, "App Leftovers"),
            entry(21.0, .downloads, .moveToTrash, gb(4.1), 14, "Downloads"),
        ]
    }

    // MARK: - Performance

    static func series(_ count: Int, base: Double, swing: Double, seed: Double) -> [Double] {
        (0..<count).map { i in
            let x = Double(i)
            let v = base + swing * (0.55 * sin(x / 6.5 + seed) + 0.3 * sin(x / 2.3 + seed * 2) + 0.15 * sin(x / 1.1 + seed * 3))
            return max(0.01, v)
        }
    }

    static let memory = MemorySample(total: 24 * 1_073_741_824, app: 9_800_000_000, wired: 3_100_000_000, compressed: 1_400_000_000,
                                     cached: 6_200_000_000, free: 2_600_000_000, swapUsed: 210_000_000, pressure: .normal)

    static let processes: [ProcessSample] = [
        ProcessSample(id: 4101, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpuPercent: 38.4, memory: 2_840_000_000),
        ProcessSample(id: 4102, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpuPercent: 14.2, memory: 1_920_000_000),
        ProcessSample(id: 4103, name: "Spotify", path: "/Applications/Spotify.app/Contents/MacOS/Spotify", cpuPercent: 6.1, memory: 412_000_000),
        ProcessSample(id: 4104, name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", cpuPercent: 4.8, memory: 986_000_000),
        ProcessSample(id: 4105, name: "Notion", path: "/Applications/Notion.app/Contents/MacOS/Notion", cpuPercent: 2.9, memory: 524_000_000),
        ProcessSample(id: 4106, name: "Tidy", path: Bundle.main.bundleURL.appending(path: "Contents/MacOS/Tidy").path(percentEncoded: false), cpuPercent: 1.2, memory: 96_000_000),
        ProcessSample(id: 4107, name: "node", path: nil, cpuPercent: 0.9, memory: 188_000_000),
        ProcessSample(id: 4108, name: "zoom.us", path: "/Applications/zoom.us.app/Contents/MacOS/zoom.us", cpuPercent: 0.6, memory: 302_000_000),
    ]

    // MARK: - Login Items

    static var launchItems: [LaunchItem] {
        func item(_ label: String, _ scope: LaunchItem.Scope, app: String?, dev: String?, running: Bool, loaded: Bool? = true, disabled: Bool = false) -> LaunchItem {
            LaunchItem(plist: scope.folder.appending(path: "\(label).plist"), label: label, program: nil, scope: scope,
                       runAtLoad: true, keepAlive: running, disabledInPlist: disabled, isLoaded: loaded, isRunning: running,
                       appURL: app.map { URL(filePath: "/Applications/\($0)") }, developer: dev)
        }
        return [
            item("com.google.keystone.agent", .userAgent, app: "Google Chrome.app", dev: "Google LLC", running: false),
            item("com.spotify.webhelper", .userAgent, app: "Spotify.app", dev: "Spotify AB", running: true),
            item("us.zoom.updater.login.check", .userAgent, app: "zoom.us.app", dev: "Zoom Video Communications, Inc.", running: false),
            item("com.adobe.ccxprocess", .userAgent, app: nil, dev: "Adobe Inc.", running: false, loaded: false, disabled: true),
            item("com.microsoft.update.agent", .systemAgent, app: "Microsoft Word.app", dev: "Microsoft Corporation", running: false),
            item("io.tailscale.ipn.macsys.network-extension", .systemAgent, app: "Tailscale.app", dev: "Tailscale Inc.", running: true),
            item("com.docker.vmnetd", .systemDaemon, app: nil, dev: "Docker Inc", running: true),
            item("com.microsoft.autoupdate.helper", .systemDaemon, app: nil, dev: "Microsoft Corporation", running: false),
            item("org.blenderfoundation.helper", .systemDaemon, app: "Blender.app", dev: "Stichting Blender Foundation", running: false, loaded: false),
        ]
    }

    static let openAtLogin: [OpenAtLoginApp] = [
        OpenAtLoginApp(name: "Spotify", path: "/Applications/Spotify.app"),
        OpenAtLoginApp(name: "Notion Calendar", path: "/Applications/Notion Calendar.app"),
        OpenAtLoginApp(name: "Tailscale", path: "/Applications/Tailscale.app"),
    ]
}
#endif
