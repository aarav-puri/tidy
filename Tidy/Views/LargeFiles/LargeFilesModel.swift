import SwiftUI
import Observation

enum AgeFilter: Int, CaseIterable, Identifiable {
    case any = 0, threeMonths = 90, sixMonths = 180, oneYear = 365, twoYears = 730

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .any: "Any Time"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .oneYear: "1 Year"
        case .twoYears: "2 Years"
        }
    }
}

@MainActor @Observable
final class LargeFilesModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    private(set) var files: [FoundFile] = []
    private(set) var scannedMinimum: Int64 = 0
    private(set) var roots: [URL] = []
    var minimumMB = 500
    var kind: FileKind?
    var age: AgeFilter = .any
    var location: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var sizeOptions: [Int] {
        [50, 100, 250, 500, 1_000, 5_000].filter { Int64($0) * 1_000_000 >= scannedMinimum }
    }

    var filtered: [FoundFile] {
        let minimum = Int64(minimumMB) * 1_000_000
        let cutoff = age == .any ? nil : Calendar.current.date(byAdding: .day, value: -age.rawValue, to: .now)
        return files.filter { file in
            guard file.size >= minimum else { return false }
            if let kind, file.kind != kind { return false }
            if let location, !file.url.path(percentEncoded: false).hasPrefix(location) { return false }
            if let cutoff {
                // Prefer the Spotlight last-opened date; fall back to modification date.
                let reference = file.lastOpened ?? file.modified
                if reference > cutoff { return false }
            }
            return true
        }
    }

    func scan() {
        guard !app.isDemo else { return }
        task?.cancel()
        files = []
        let minimum = Int64(max(app.settings.largeFileMinimumMB, 10)) * 1_000_000
        scannedMinimum = minimum
        if Int64(minimumMB) * 1_000_000 < minimum { minimumMB = Int(minimum / 1_000_000) }
        roots = app.settings.scanRoots
        phase = .scanning(progress: nil, detail: "Starting…")
        let scanner = LargeFileScanner(walker: app.settings.walker(minimumBytes: minimum))
        task = Task {
            for await event in scanner.scan() {
                switch event {
                case .progress(let visited, let current):
                    phase = .scanning(progress: nil, detail: "\(visited.formatted()) items checked · \(current.isEmpty ? "" : Format.path(URL(filePath: current)))")
                case .found(let batch):
                    files.append(contentsOf: batch)
                case .finished:
                    break
                }
            }
            guard !Task.isCancelled else { return }
            phase = .finished(.now)
            if app.settings.notifyWhenScansFinish {
                NotificationService.notifyIfInactive(title: "Large File Scan Complete", body: "Found \(Format.count(files.count, singular: "large file")).")
            }
        }
    }

    func cancel() {
        task?.cancel()
        if phase.isScanning { phase = .cancelled }
    }

    func requestRemoval(_ ids: Set<URL>) {
        let selected = files.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        var request = RemovalRequest(kind: .largeFiles, title: "Large & Old Files",
                                     entries: selected.map {
                                         RemovalRequest.Entry(candidate: RemovalCandidate(url: $0.url, size: $0.size),
                                                              name: $0.name, detail: $0.location)
                                     })
        request.onComplete = { [weak self] outcome in
            let removed = Set(outcome.removed.map(\.originalPath))
            self?.files.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
        }
        app.requestRemoval(request)
    }
}

#if DEBUG
extension LargeFilesModel {
    func loadDemo() {
        files = DemoData.largeFiles
        scannedMinimum = 100 * DemoData.MB
        minimumMB = 500
        roots = [DemoData.home]
        phase = .finished(.now)
    }
}
#endif
