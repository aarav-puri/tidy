import Foundation

enum RemovalMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case moveToTrash
    case deleteImmediately

    var id: String { rawValue }
    var title: String {
        switch self {
        case .moveToTrash: "Move to Trash"
        case .deleteImmediately: "Delete Immediately"
        }
    }
}

enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case smartCleanup, largeFiles, downloads, duplicates, storageExplorer, uninstall, leftovers, emptyTrash

    var title: String {
        switch self {
        case .smartCleanup: "Smart Cleanup"
        case .largeFiles: "Large & Old Files"
        case .downloads: "Downloads"
        case .duplicates: "Duplicates"
        case .storageExplorer: "Storage Explorer"
        case .uninstall: "App Uninstall"
        case .leftovers: "App Leftovers"
        case .emptyTrash: "Empty Trash"
        }
    }

    var symbol: String {
        switch self {
        case .smartCleanup: "eraser"
        case .largeFiles: "doc.badge.clock"
        case .downloads: "arrow.down.circle"
        case .duplicates: "square.on.square"
        case .storageExplorer: "chart.pie"
        case .uninstall: "xmark.app"
        case .leftovers: "puzzlepiece.extension"
        case .emptyTrash: "trash"
        }
    }
}

struct RemovedItem: Codable, Sendable, Hashable, Identifiable {
    var id: String { originalPath }
    let originalPath: String
    /// Location in the Trash when the item was moved there (recoverable).
    let trashedPath: String?
    let size: Int64
}

struct HistoryEntry: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let kind: ActivityKind
    let mode: RemovalMode
    let bytes: Int64
    let items: [RemovedItem]
    let failureCount: Int
    var detail: String?
}
