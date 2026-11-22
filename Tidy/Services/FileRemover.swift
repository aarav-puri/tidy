import Foundation

/// An item the user has explicitly chosen to remove.
struct RemovalCandidate: Sendable, Hashable, Identifiable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var bundleIdentifier: String?
    var allowApplicationBundle = false
}

struct RemovalFailure: Sendable, Hashable, Identifiable {
    var id: URL { url }
    let url: URL
    let reason: String
}

struct RemovalOutcome: Sendable {
    var removed: [RemovedItem] = []
    var failures: [RemovalFailure] = []
    var bytes: Int64 { removed.reduce(0) { $0 + $1.size } }
}

/// The only component in Tidy that removes files. It re-validates every item
/// against `SafetyPolicy` and the set of running apps at the moment of removal,
/// so stale scan results can never cause an unsafe deletion.
struct FileRemover: Sendable {
    let policy: SafetyPolicy

    func remove(
        _ candidates: [RemovalCandidate],
        mode: RemovalMode,
        runningBundleIDs: Set<String>,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async -> RemovalOutcome {
        var outcome = RemovalOutcome()
        let fm = FileManager()
        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled {
                outcome.failures.append(.init(url: candidate.url, reason: "Cancelled before removal."))
                continue
            }
            progress(Double(index) / Double(max(candidates.count, 1)))
            if let id = candidate.bundleIdentifier, runningBundleIDs.contains(where: { $0 == id || $0.hasPrefix(id + ".") }) {
                outcome.failures.append(.init(url: candidate.url, reason: "The app is open. Quit it and try again."))
                continue
            }
            if case .denied(let reason) = policy.evaluate(candidate.url, allowApplicationBundles: candidate.allowApplicationBundle) {
                outcome.failures.append(.init(url: candidate.url, reason: reason))
                continue
            }
            do {
                switch mode {
                case .moveToTrash:
                    var resulting: NSURL?
                    try fm.trashItem(at: candidate.url, resultingItemURL: &resulting)
                    outcome.removed.append(.init(originalPath: candidate.url.path(percentEncoded: false),
                                                 trashedPath: resulting?.path, size: candidate.size))
                case .deleteImmediately:
                    try fm.removeItem(at: candidate.url)
                    outcome.removed.append(.init(originalPath: candidate.url.path(percentEncoded: false),
                                                 trashedPath: nil, size: candidate.size))
                }
                Log.cleanup.info("Removed \(candidate.url.path(percentEncoded: false), privacy: .private) mode=\(mode.rawValue)")
            } catch {
                Log.cleanup.error("Failed to remove \(candidate.url.path(percentEncoded: false), privacy: .private): \(error.localizedDescription)")
                outcome.failures.append(.init(url: candidate.url, reason: error.friendlyDescription))
            }
        }
        progress(1)
        return outcome
    }

    /// Moves a previously trashed item back to its original location.
    static func restore(_ item: RemovedItem) throws {
        guard let trashed = item.trashedPath else {
            throw TidyError.commandFailed("This item was deleted and can't be put back.")
        }
        let source = URL(filePath: trashed)
        let destination = URL(filePath: item.originalPath)
        guard FileSystem.exists(source) else {
            throw TidyError.commandFailed("The item is no longer in the Trash.")
        }
        guard !FileSystem.exists(destination) else {
            throw TidyError.commandFailed("An item with the same name already exists there.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
