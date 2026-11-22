import Foundation

/// How safe an item is to remove. Classification is conservative: anything Tidy
/// cannot confidently explain is never `recommended`.
enum RiskLevel: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case recommended = 0
    case review = 1
    case protected = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .review: "Review Required"
        case .protected: "Protected"
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "checkmark.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .protected: "lock.fill"
        }
    }

    var summary: String {
        switch self {
        case .recommended: "Safe to remove. Apps recreate these as needed."
        case .review: "May contain data you want. Check before removing."
        case .protected: "Never removed."
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CleanupCategoryKind: String, Sendable, CaseIterable, Identifiable, Codable {
    case userCaches, logs, temporaryFiles, partialDownloads, developer, deviceBackups, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: "App Caches"
        case .logs: "Logs & Diagnostic Reports"
        case .temporaryFiles: "Temporary Files"
        case .partialDownloads: "Unfinished Downloads"
        case .developer: "Developer Files"
        case .deviceBackups: "iPhone & iPad Backups"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .userCaches: "shippingbox"
        case .logs: "doc.plaintext"
        case .temporaryFiles: "clock.arrow.circlepath"
        case .partialDownloads: "arrow.down.circle.dotted"
        case .developer: "hammer"
        case .deviceBackups: "iphone"
        case .trash: "trash"
        }
    }

    var explanation: String {
        switch self {
        case .userCaches:
            "Temporary data apps keep to run faster. Apps rebuild it as needed."
        case .logs:
            "Activity records from apps and macOS, mainly useful for troubleshooting."
        case .temporaryFiles:
            "Files apps created for short-term work and haven't used in days."
        case .partialDownloads:
            "Downloads that never finished and can't be opened."
        case .developer:
            "Build data and caches from Xcode and developer tools."
        case .deviceBackups:
            "Backups of your iPhone or iPad stored on this Mac."
        case .trash:
            "Items you've moved to the Trash."
        }
    }

    var scanningLabel: String {
        switch self {
        case .userCaches: "Measuring app caches…"
        case .logs: "Reviewing logs…"
        case .temporaryFiles: "Checking temporary files…"
        case .partialDownloads: "Looking for unfinished downloads…"
        case .developer: "Checking developer files…"
        case .deviceBackups: "Looking for device backups…"
        case .trash: "Measuring the Trash…"
        }
    }
}

struct CleanupItem: Identifiable, Sendable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: Int64
    let modified: Date?
    let risk: RiskLevel
    let reason: String
    let category: CleanupCategoryKind
    var bundleIdentifier: String?
    var isSelected: Bool

    var isSelectable: Bool { risk != .protected }
}

struct CleanupCategoryResult: Identifiable, Sendable {
    var id: CleanupCategoryKind { kind }
    let kind: CleanupCategoryKind
    var items: [CleanupItem]
    /// Items found but never removable; listed for transparency.
    var protectedItems: [CleanupItem] = []
    /// Locations that couldn't be examined, with an explanation.
    var unavailable: [String] = []

    var totalSize: Int64 { items.filter(\.isSelectable).reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.count(where: \.isSelected) }
    var removableItems: [CleanupItem] { items.filter(\.isSelectable) }
}

enum ScanPhase: Equatable, Sendable {
    case idle
    case scanning(progress: Double?, detail: String)
    case finished(Date)
    case cancelled
    case failed(String)

    var isScanning: Bool { if case .scanning = self { true } else { false } }
    var hasResults: Bool {
        switch self {
        case .finished, .cancelled: true
        default: false
        }
    }
}
