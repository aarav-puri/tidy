import SwiftUI
import Observation

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all, installers, archives, media, documents, older
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .installers: "Installers & Disk Images"
        case .archives: "Archives"
        case .media: "Media"
        case .documents: "Documents"
        case .older: "Older Than 30 Days"
        }
    }
}

@MainActor @Observable
final class DownloadsModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    private(set) var items: [DownloadItem] = []
    private(set) var accessDenied = false
    var filter: DownloadFilter = .all

    init(app: AppModel) { self.app = app }

    var filtered: [DownloadItem] {
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        return items.filter { item in
            switch filter {
            case .all: true
            case .installers: item.kind == .installer || item.kind == .diskImage
            case .archives: item.kind == .archive
            case .media: item.kind == .video || item.kind == .image || item.kind == .audio
            case .documents: item.kind == .document
            case .older: (item.added ?? item.modified) < cutoff
            }
        }
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func load() {
        guard !app.isDemo else { return }
        phase = .scanning(progress: nil, detail: "Reading Downloads…")
        Task {
            switch await DownloadsScanner.scan() {
            case .success(let items):
                self.items = items
                accessDenied = false
            case .failure:
                accessDenied = true
            }
            phase = .finished(.now)
        }
    }

    func note(for item: DownloadItem) -> String? {
        switch item.kind {
        case .installer, .diskImage: "Usually not needed after installing."
        case .archive: "Not needed if already opened."
        default: nil
        }
    }

    func requestRemoval(_ ids: Set<URL>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        var request = RemovalRequest(kind: .downloads, title: "Downloads",
                                     entries: selected.map {
                                         RemovalRequest.Entry(candidate: RemovalCandidate(url: $0.url, size: $0.size),
                                                              name: $0.name, detail: $0.kindDescription + ($0.source.map { " · from \($0)" } ?? ""))
                                     })
        request.onComplete = { [weak self] outcome in
            let removed = Set(outcome.removed.map(\.originalPath))
            self?.items.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
        }
        app.requestRemoval(request)
    }
}

#if DEBUG
extension DownloadsModel {
    func loadDemo() {
        items = DemoData.downloads
        accessDenied = false
        phase = .finished(.now)
    }
}
#endif
