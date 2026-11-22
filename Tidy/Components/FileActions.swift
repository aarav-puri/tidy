import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum FileActions {
    @MainActor static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @MainActor static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor static func copyPath(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
    }
}

/// Standard Finder-style context menu items for files.
struct FileContextMenu: View {
    let urls: [URL]
    var quickLook: ((URL) -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        if urls.count == 1, let url = urls.first {
            Button("Open", systemImage: "arrow.up.forward.app") { FileActions.open(url) }
            if let quickLook {
                Button("Quick Look", systemImage: "eye") { quickLook(url) }
            }
        }
        Button("Show in Finder", systemImage: "folder") { FileActions.reveal(urls) }
        Button(urls.count == 1 ? "Copy Path" : "Copy Paths", systemImage: "doc.on.doc") { FileActions.copyPath(urls) }
        if let onRemove {
            Divider()
            Button(urls.count == 1 ? "Move to Trash…" : "Move \(urls.count) Items to Trash…", systemImage: "trash", role: .destructive, action: onRemove)
        }
    }
}

/// Caches Finder icons for files and apps.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let key = url.path(percentEncoded: false)
        if let cached = cache[key] { return cached }
        let image: NSImage
        if FileManager.default.fileExists(atPath: key) {
            image = NSWorkspace.shared.icon(forFile: key)
        } else if url.pathExtension.isEmpty || url.hasDirectoryPath {
            image = NSWorkspace.shared.icon(for: .folder)
        } else {
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
        }
        if cache.count > 2000 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: IconCache.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
