import Foundation

/// User-presentable errors with recovery suggestions.
enum TidyError: LocalizedError, Sendable {
    case permissionDenied(String)
    case notFound(String)
    case protectedItem(String, reason: String)
    case appRunning(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let path): "You don't have permission to access “\(path)”."
        case .notFound(let path): "“\(path)” no longer exists."
        case .protectedItem(let path, let reason): "“\(path)” is protected. \(reason)"
        case .appRunning(let name): "\(name) is currently open."
        case .commandFailed(let message): message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied: "Turn on Full Disk Access in System Settings > Privacy & Security."
        case .appRunning: "Quit the app and try again."
        default: nil
        }
    }
}

extension Error {
    /// A concise, human-readable description suitable for inline display.
    var friendlyDescription: String {
        let ns = self as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return "The item no longer exists."
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return "Permission denied."
            case NSFileWriteVolumeReadOnlyError: return "The volume is read-only."
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) {
            return "Permission denied."
        }
        return localizedDescription
    }
}
