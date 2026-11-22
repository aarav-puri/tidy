import Foundation
import Observation

/// Persists a local record of every removal Tidy performs. Stored in
/// ~/Library/Application Support/Tidy/history.json and never transmitted.
@MainActor @Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    /// Demo content is never written to disk.
    private var isDemo = false
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Tidy", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appending(path: "history.json")
        load()
    }

    var lastCleanup: HistoryEntry? { entries.first }

    var totalReclaimed: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    func record(_ outcome: RemovalOutcome, kind: ActivityKind, mode: RemovalMode, detail: String? = nil) {
        guard !outcome.removed.isEmpty else { return }
        let entry = HistoryEntry(id: UUID(), date: .now, kind: kind, mode: mode, bytes: outcome.bytes,
                                 items: outcome.removed, failureCount: outcome.failures.count, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > 500 { entries.removeLast(entries.count - 500) }
        save()
    }

    func recordTrashEmptied(bytes: Int64) {
        let entry = HistoryEntry(id: UUID(), date: .now, kind: .emptyTrash, mode: .deleteImmediately, bytes: bytes,
                                 items: [], failureCount: 0, detail: "Emptied the Trash")
        entries.insert(entry, at: 0)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard !isDemo else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

#if DEBUG
extension HistoryStore {
    func loadDemo() {
        isDemo = true
        entries = DemoData.history
    }
}
#endif
