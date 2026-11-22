import SwiftUI
import Observation

enum DuplicateKindFilter: String, CaseIterable, Identifiable {
    case all, images, documents, videos, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Files"
        case .images: "Images"
        case .documents: "Documents"
        case .videos: "Videos"
        case .other: "Other"
        }
    }

    func matches(_ kind: FileKind) -> Bool {
        switch self {
        case .all: true
        case .images: kind == .image
        case .documents: kind == .document
        case .videos: kind == .video
        case .other: ![.image, .document, .video].contains(kind)
        }
    }
}

@MainActor @Observable
final class DuplicatesModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    private(set) var groups: [DuplicateGroup] = []
    private(set) var filesExamined = 0
    /// Files the user has marked for removal. Never contains every copy in a group.
    private(set) var marked: Set<URL> = []
    var filter: DuplicateKindFilter = .all
    var lastRefusal: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var filteredGroups: [DuplicateGroup] { groups.filter { filter.matches($0.kind) } }
    var wastedSpace: Int64 { groups.reduce(0) { $0 + $1.wastedSpace } }
    var markedFiles: [FoundFile] { groups.flatMap { $0.files.filter { marked.contains($0.url) } } }
    var markedSize: Int64 { markedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !app.isDemo else { return }
        task?.cancel()
        groups = []
        marked = []
        phase = .scanning(progress: nil, detail: "Starting…")
        let finder = DuplicateFinder(walker: app.settings.walker(minimumBytes: Int64(max(app.settings.duplicateMinimumMB, 0)) * 1_000_000 + 1))
        task = Task {
            for await event in finder.scan() {
                switch event {
                case .stage(let detail, let progress):
                    phase = .scanning(progress: progress, detail: detail)
                case .groups(let found):
                    groups.append(contentsOf: found)
                case .finished(let examined, _):
                    filesExamined = examined
                }
            }
            guard !Task.isCancelled else { return }
            groups.sort { $0.wastedSpace > $1.wastedSpace }
            phase = .finished(.now)
            if app.settings.notifyWhenScansFinish {
                NotificationService.notifyIfInactive(title: "Duplicate Scan Complete",
                                                     body: "\(Format.bytes(wastedSpace)) used by extra copies.")
            }
        }
    }

    func cancel() {
        task?.cancel()
        if phase.isScanning { phase = .cancelled }
    }

    func isMarked(_ file: FoundFile) -> Bool { marked.contains(file.url) }

    /// Marks or unmarks a copy. Refuses to mark the last unmarked copy in a group.
    func setMarked(_ file: FoundFile, in group: DuplicateGroup, _ value: Bool) {
        if value {
            let unmarked = group.files.filter { !marked.contains($0.url) }
            guard unmarked.count > 1 else {
                lastRefusal = "At least one copy of “\(file.name)” must be kept."
                return
            }
            marked.insert(file.url)
        } else {
            marked.remove(file.url)
        }
    }

    /// Explicit user action: keep the oldest copy in each visible group and mark the rest.
    func markAllButOldest() {
        for group in filteredGroups {
            for file in group.files.dropFirst() { marked.insert(file.url) }
            marked.remove(group.files[0].url)
        }
    }

    func clearMarks() { marked.removeAll() }

    func requestRemoval() {
        var entries: [RemovalRequest.Entry] = []
        for group in groups {
            let toRemove = group.files.filter { marked.contains($0.url) }
            guard !toRemove.isEmpty else { continue }
            // Safeguard: verify a kept copy still exists with the same size before removing others.
            let kept = group.files.filter { !marked.contains($0.url) }
            guard kept.contains(where: { FileSystem.info($0.url)?.size == group.size }) else {
                lastRefusal = "The copy of “\(group.files[0].name)” you're keeping has changed. Scan again."
                continue
            }
            let keptPath = kept.first.map { Format.path($0.url) } ?? ""
            entries += toRemove.map {
                RemovalRequest.Entry(candidate: RemovalCandidate(url: $0.url, size: $0.size), name: $0.name,
                                     detail: "\($0.location) · keeping \(keptPath)")
            }
        }
        guard !entries.isEmpty else { return }
        var request = RemovalRequest(kind: .duplicates, title: "Duplicate Files", entries: entries)
        request.note = "One copy of every file is kept."
        request.onComplete = { [weak self] outcome in self?.apply(outcome) }
        app.requestRemoval(request)
    }

    private func apply(_ outcome: RemovalOutcome) {
        let removed = Set(outcome.removed.map(\.originalPath))
        for index in groups.indices {
            groups[index].files.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
        }
        groups.removeAll { $0.files.count < 2 }
        marked = marked.filter { !removed.contains($0.path(percentEncoded: false)) }
    }
}

#if DEBUG
extension DuplicatesModel {
    func loadDemo() {
        groups = DemoData.duplicateGroups
        filesExamined = 48_210
        marked = Set(groups.prefix(2).flatMap { $0.files.dropFirst().map(\.url) })
        phase = .finished(.now)
    }
}
#endif
