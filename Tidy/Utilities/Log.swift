import os

/// Unified logging categories. Logs stay on this Mac (viewable in Console.app).
enum Log {
    private static let subsystem = "dev.tidy.Tidy"
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    static let apps = Logger(subsystem: subsystem, category: "apps")
    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    static let general = Logger(subsystem: subsystem, category: "general")
}
