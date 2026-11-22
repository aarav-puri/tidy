import SwiftUI
import Observation

@MainActor @Observable
final class SmartCleanupModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    var categories: [CleanupCategoryResult] = []
    private(set) var trashSize: Int64?
    private(set) var trashMeasured = false
    private(set) var unavailable: [String] = []
    private(set) var lastScan: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var reclaimable: Int64 { categories.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.size } } }
    var candidateCount: Int { categories.reduce(0) { $0 + $1.items.count } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.selectedCount } }
    var protectedItems: [CleanupItem] { categories.flatMap(\.protectedItems) }
    var hasResults: Bool { phase.hasResults || !categories.isEmpty }

    func item(_ id: URL?) -> CleanupItem? {
        guard let id else { return nil }
        for category in categories {
            if let item = category.items.first(where: { $0.id == id }) ?? category.protectedItems.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    func scan() {
        guard !app.isDemo else { return }
        task?.cancel()
        categories = []
        unavailable = []
        trashSize = nil
        trashMeasured = false
        phase = .scanning(progress: 0, detail: "Preparing…")
        let scanner = CleanupScanner(running: app.runningApps(), excludedPaths: app.settings.excludedPaths,
                                     protectedPaths: app.settings.protectedPaths)
        task = Task {
            for await event in scanner.scan() {
                switch event {
                case .progress(let fraction, let label):
                    phase = .scanning(progress: fraction, detail: label)
                case .category(var result):
                    unavailable.append(contentsOf: result.unavailable)
                    if result.kind == .trash {
                        trashMeasured = result.unavailable.isEmpty
                        trashSize = result.items.first?.size ?? (trashMeasured ? 0 : nil)
                        continue
                    }
                    let all = result.items
                    result.items = all.filter(\.isSelectable)
                    result.protectedItems = all.filter { !$0.isSelectable }
                    if !result.items.isEmpty || !result.protectedItems.isEmpty {
                        categories.append(result)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            lastScan = .now
            phase = .finished(.now)
            Log.scan.info("Smart Cleanup found \(self.candidateCount) candidates, \(self.reclaimable) bytes")
            if app.settings.notifyWhenScansFinish {
                NotificationService.notifyIfInactive(title: "Scan Complete",
                                                     body: "\(Format.bytes(reclaimable)) of potential cleanup items found.")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isScanning { phase = .cancelled }
    }

    func setAll(_ selected: Bool, risk: RiskLevel? = nil) {
        for c in categories.indices {
            for i in categories[c].items.indices where risk == nil || categories[c].items[i].risk == risk {
                categories[c].items[i].isSelected = selected
            }
        }
    }

    func requestCleanup() {
        let selected = categories.flatMap { $0.items.filter(\.isSelected) }
        guard !selected.isEmpty else { return }
        let entries = selected.map { item in
            RemovalRequest.Entry(candidate: RemovalCandidate(url: item.url, size: item.size, bundleIdentifier: item.bundleIdentifier),
                                 name: item.name, detail: "\(item.category.title) · \(Format.parentPath(item.url))")
        }
        var request = RemovalRequest(kind: .smartCleanup, title: "Smart Cleanup", entries: entries)
        request.onComplete = { [weak self] outcome in self?.applyRemoval(outcome) }
        app.requestRemoval(request)
    }

    func applyRemoval(_ outcome: RemovalOutcome) {
        let removed = Set(outcome.removed.map(\.originalPath))
        for c in categories.indices {
            categories[c].items.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
        }
        categories.removeAll { $0.items.isEmpty && $0.protectedItems.isEmpty }
    }

    func trashEmptied() {
        trashSize = 0
    }
}

#if DEBUG
extension SmartCleanupModel {
    func loadDemo() {
        categories = DemoData.cleanupCategories
        unavailable = []
        trashSize = DemoData.gb(3.6)
        trashMeasured = true
        lastScan = .now.addingTimeInterval(-120)
        phase = .finished(lastScan!)
    }
}
#endif
