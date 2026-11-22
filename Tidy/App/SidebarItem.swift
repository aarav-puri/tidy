import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case smartCleanup, storageExplorer, largeFiles, duplicates, downloads
    case appManager, leftovers, loginItems
    case performance, maintenance
    case history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .smartCleanup: "Smart Cleanup"
        case .storageExplorer: "Storage Explorer"
        case .largeFiles: "Large & Old Files"
        case .duplicates: "Duplicates"
        case .downloads: "Downloads"
        case .appManager: "App Manager"
        case .leftovers: "App Leftovers"
        case .loginItems: "Login Items"
        case .performance: "Performance"
        case .maintenance: "Maintenance"
        case .history: "Activity History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .smartCleanup: "eraser"
        case .storageExplorer: "chart.pie"
        case .largeFiles: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .downloads: "arrow.down.circle"
        case .appManager: "square.grid.2x2"
        case .leftovers: "puzzlepiece.extension"
        case .loginItems: "power"
        case .performance: "waveform.path.ecg"
        case .maintenance: "stethoscope"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

    /// Tile color, following System Settings' colored icon tiles.
    var tint: Color {
        switch self {
        case .dashboard: .blue
        case .smartCleanup: .teal
        case .storageExplorer: .purple
        case .largeFiles: .orange
        case .duplicates: .indigo
        case .downloads: .green
        case .appManager: .pink
        case .leftovers: .brown
        case .loginItems: .gray
        case .performance: .red
        case .maintenance: .yellow
        case .history: .cyan
        case .settings: .gray
        }
    }

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", storage = "Storage", applications = "Applications", system = "System", other = "Other"
        var id: String { rawValue }
        var items: [SidebarItem] {
            switch self {
            case .overview: [.dashboard]
            case .storage: [.smartCleanup, .storageExplorer, .largeFiles, .duplicates, .downloads]
            case .applications: [.appManager, .leftovers, .loginItems]
            case .system: [.performance, .maintenance]
            case .other: [.history, .settings]
            }
        }
    }
}
