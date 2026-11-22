import Foundation

/// Shared formatting helpers. All functions are pure and safe to call from any thread.
enum Format {
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    /// Memory sizes use binary units, matching About This Mac and Activity Monitor.
    static func memory(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        "\(bytes(Int64(max(0, bytesPerSecond))))/s"
    }

    static func percent(_ fraction: Double, digits: Int = 0) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    static func count(_ value: Int, singular: String, plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Replaces the home directory prefix with `~` the way Finder and Terminal do.
    static func path(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    static func parentPath(_ url: URL) -> String {
        path(url.deletingLastPathComponent())
    }
}
