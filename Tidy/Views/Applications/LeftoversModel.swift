import SwiftUI
import Observation

@MainActor @Observable
final class LeftoversModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    var groups: [LeftoverGroup] = []
    private(set) var containersSkipped = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    var selectedFiles: [AssociatedFile] { groups.flatMap { $0.items.filter(\.isSelected) } }

    func scan() {
        guard !app.isDemo else { return }
        task?.cancel()
        phase = .scanning(progress: nil, detail: "Checking installed apps…")
        let running = app.runningApps().bundleIdentifiers
        let includeContainers = app.hasFullDiskAccess
        containersSkipped = !includeContainers
        task = Task {
            let installed = await Task.detached { AppDiscovery.installedIdentifiers() }.value
            phase = .scanning(progress: nil, detail: "Looking for data from removed apps…")
            let scanner = LeftoverScanner(installedIdentifiers: installed, runningIdentifiers: running,
                                          registeredCheck: { id in
                                              !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).isEmpty
                                          },
                                          includeContainers: includeContainers)
            let result = await scanner.scan()
            guard !Task.isCancelled else { return }
            groups = result
            phase = .finished(.now)
        }
    }

    func cancel() {
        task?.cancel()
        if phase.isScanning { phase = groups.isEmpty ? .idle : .cancelled }
    }

    func selectHighConfidence() {
        for g in groups.indices where groups[g].confidence == .high {
            for i in groups[g].items.indices { groups[g].items[i].isSelected = true }
        }
    }

    func deselectAll() {
        for g in groups.indices { for i in groups[g].items.indices { groups[g].items[i].isSelected = false } }
    }

    func requestRemoval() {
        var entries: [RemovalRequest.Entry] = []
        for group in groups {
            for file in group.items where file.isSelected {
                entries.append(RemovalRequest.Entry(candidate: RemovalCandidate(url: file.url, size: file.size, bundleIdentifier: group.identifier),
                                                    name: file.url.lastPathComponent,
                                                    detail: "\(file.kind.title) · \(group.identifier)",
                                                    warnings: file.kind.caution.map { [$0] } ?? []))
            }
        }
        guard !entries.isEmpty else { return }
        var request = RemovalRequest(kind: .leftovers, title: "App Leftovers", entries: entries)
        request.onComplete = { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.originalPath))
            for g in self.groups.indices {
                self.groups[g].items.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
            }
            self.groups.removeAll { $0.items.isEmpty }
        }
        app.requestRemoval(request)
    }
}

#if DEBUG
extension LeftoversModel {
    func loadDemo() {
        groups = DemoData.leftovers
        containersSkipped = false
        phase = .finished(.now)
    }
}
#endif
