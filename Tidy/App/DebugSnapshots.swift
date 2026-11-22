#if DEBUG
import AppKit
import SwiftUI

/// Development aid: renders the main window to PNG files for visual review.
/// Launch with `-TidySnapshotDir <dir> [-TidyPages a,b] [-TidyScan YES] [-TidyAppearance dark]`.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(app: AppModel) {
        let defaults = UserDefaults.standard
        guard let dir = defaults.string(forKey: "TidySnapshotDir") else { return }
        if let appearance = defaults.string(forKey: "TidyAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        let pages = (defaults.string(forKey: "TidyPages")?.split(separator: ",").map(String.init))
            ?? SidebarItem.allCases.filter { $0 != .settings }.map(\.rawValue)
        Task {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.frame.width > 600 }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(2))
            if defaults.bool(forKey: "TidyScan") {
                app.scanMac()
                app.apps.load()
                for _ in 0..<240 where app.isScanningMac || app.apps.phase.isScanning {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            if defaults.bool(forKey: "TidyScanFiles") {
                app.largeFiles.scan()
                app.duplicates.scan()
                app.explorer.scan(FileSystem.home)
                for _ in 0..<600 where app.largeFiles.phase.isScanning || app.duplicates.phase.isScanning || app.explorer.phase.isScanning {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            if let dump = defaults.string(forKey: "TidyDump") {
                var lines: [String] = []
                for c in app.cleanup.categories {
                    lines.append("## \(c.kind.title)")
                    for i in c.items + c.protectedItems {
                        lines.append("\(i.risk.title)\t\(i.isSelected ? "[x]" : "[ ]")\t\(Format.bytes(i.size))\t\(Format.path(i.url))\t\(i.reason)")
                    }
                }
                lines.append("## Leftovers")
                for g in app.leftovers.groups {
                    lines.append("\(g.confidence.title)\t\(Format.bytes(g.totalSize))\t\(g.identifier)\t" + g.items.map { Format.path($0.url) }.joined(separator: ", "))
                }
                try? lines.joined(separator: "\n").write(toFile: dump, atomically: true, encoding: .utf8)
            }
            for page in pages {
                guard let item = SidebarItem(rawValue: page) else { continue }
                app.selection = item
                try? await Task.sleep(for: .seconds(3))
                capture(to: URL(filePath: dir).appending(path: "\(page).png"))
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("capture failed: windows=\(NSApp.windows.map { "\($0.className) \($0.frame) visible=\($0.isVisible)" })")
            return
        }
        // Prefer the window server's own composite (it includes Liquid Glass).
        // A process may capture its own windows without Screen Recording access.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let create = unsafeBitCast(sym, to: CreateImage.self)
            // kCGWindowListOptionIncludingWindow = 8, imageBoundsIgnoreFraming | imageBestResolution = 1 | 8
            if let image = create(.null, 8, UInt32(window.windowNumber), 9)?.takeRetainedValue() {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("[\(url.lastPathComponent)] window server capture \(image.width)x\(image.height)")
                return
            }
        }
        print("[\(url.lastPathComponent)] window=\(window.frame) content=\(window.contentView?.frame ?? .zero) fitting=\(window.contentView?.fittingSize ?? .zero) screen=\(window.screen?.visibleFrame ?? .zero)")
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
