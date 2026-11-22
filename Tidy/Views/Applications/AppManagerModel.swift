import SwiftUI
import Observation

enum AppSort: String, CaseIterable, Identifiable {
    case name, size, lastUsed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .lastUsed: "Last Opened"
        }
    }
}

@MainActor @Observable
final class AppManagerModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var phase: ScanPhase = .idle
    private(set) var apps: [InstalledApp] = []
    var search = ""
    var showSystemApps = false
    var associated: [String: [AssociatedFile]] = [:]
    private(set) var loadingAssociated: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var visibleApps: [InstalledApp] {
        apps.filter { (showSystemApps || !$0.isSystemApp) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                                                                || ($0.developer ?? "").localizedCaseInsensitiveContains(search)) }
    }

    var totalSize: Int64 { apps.filter { !$0.isSystemApp }.reduce(0) { $0 + ($1.size ?? 0) } }

    func load() {
        guard !app.isDemo else { return }
        task?.cancel()
        phase = .scanning(progress: nil, detail: "Finding applications…")
        task = Task {
            var measured = 0
            for await event in AppDiscovery.discover() {
                switch event {
                case .apps(let list):
                    apps = list
                case .update(let updated):
                    if let index = apps.firstIndex(where: { $0.id == updated.id }) { apps[index] = updated }
                    measured += 1
                    phase = .scanning(progress: Double(measured) / Double(max(apps.count, 1)), detail: "Measuring \(updated.name)…")
                case .finished:
                    break
                }
            }
            guard !Task.isCancelled else { return }
            phase = .finished(.now)
        }
    }

    func loadAssociated(for installed: InstalledApp, force: Bool = false) {
        guard !app.isDemo else { return }
        guard force || associated[installed.id] == nil, !loadingAssociated.contains(installed.id) else { return }
        loadingAssociated.insert(installed.id)
        Task {
            let files = await AppDiscovery.associatedFiles(for: installed)
            associated[installed.id] = files
            loadingAssociated.remove(installed.id)
            if let index = apps.firstIndex(where: { $0.id == installed.id }) {
                apps[index].relatedSize = files.filter { $0.kind != .bundle }.reduce(0) { $0 + $1.size }
            }
        }
    }

    func runningInstance(of installed: InstalledApp) -> NSRunningApplication? {
        guard let id = installed.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }

    func requestUninstall(_ installed: InstalledApp) {
        guard !installed.isProtected, let files = associated[installed.id] else { return }
        let selected = files.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        let entries = selected.map { file in
            RemovalRequest.Entry(candidate: RemovalCandidate(url: file.url, size: file.size, bundleIdentifier: installed.bundleIdentifier,
                                                             allowApplicationBundle: file.kind == .bundle),
                                 name: file.kind == .bundle ? installed.name : file.url.lastPathComponent,
                                 detail: "\(file.kind.title) · \(Format.parentPath(file.url))",
                                 warnings: file.kind.caution.map { [$0] } ?? [])
        }
        let includesBundle = selected.contains { $0.kind == .bundle }
        var request = RemovalRequest(kind: .uninstall, title: includesBundle ? "Uninstall \(installed.name)" : "Remove \(installed.name) Data",
                                     entries: entries, forceTrash: true)
        request.onComplete = { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.originalPath))
            if removed.contains(installed.url.path(percentEncoded: false)) {
                self.apps.removeAll { $0.id == installed.id }
                self.associated[installed.id] = nil
            } else {
                self.associated[installed.id]?.removeAll { removed.contains($0.url.path(percentEncoded: false)) }
            }
        }
        app.requestRemoval(request)
    }
}

#if DEBUG
extension AppManagerModel {
    func loadDemo() {
        apps = DemoData.apps
        phase = .finished(.now)
    }
}
#endif
