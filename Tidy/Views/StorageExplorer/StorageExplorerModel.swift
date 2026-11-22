import SwiftUI
import Observation

@MainActor @Observable
final class StorageExplorerModel {
    @ObservationIgnored private unowned let app: AppModel
    private(set) var rootURL: URL = FileSystem.home
    private(set) var root: StorageNode?
    /// IDs of folders the user has drilled into, starting below the root.
    private(set) var pathIDs: [String] = []
    private(set) var phase: ScanPhase = .idle
    private(set) var scannedItems = 0
    private(set) var scannedBytes: Int64 = 0
    private(set) var skippedProtected = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var path: [StorageNode] {
        guard let root else { return [] }
        var nodes = [root]
        for id in pathIDs {
            guard let next = nodes.last?.children.first(where: { $0.id == id }) else { break }
            nodes.append(next)
        }
        return nodes
    }

    var current: StorageNode? { path.last }

    func scan(_ url: URL? = nil) {
        guard !app.isDemo else { return }
        if let url { rootURL = url }
        task?.cancel()
        root = nil
        pathIDs = []
        scannedItems = 0
        scannedBytes = 0
        phase = .scanning(progress: nil, detail: "Measuring \(Format.path(rootURL))…")
        var skip: Set<String> = [TrashService.url.path(percentEncoded: false)]
        if !app.hasFullDiskAccess {
            skip.insert(FileSystem.library.appending(path: "Containers").path(percentEncoded: false))
            skip.insert(FileSystem.library.appending(path: "Group Containers").path(percentEncoded: false))
        }
        skippedProtected = !app.hasFullDiskAccess
        for path in app.settings.excludedPaths { skip.insert(path) }
        let scanner = StorageTreeScanner(root: rootURL, skipPaths: skip)
        task = Task {
            for await event in scanner.scan() {
                switch event {
                case .progress(let items, let bytes, _):
                    scannedItems = items
                    scannedBytes = bytes
                    phase = .scanning(progress: nil, detail: "\(items.formatted()) items · \(Format.bytes(bytes))")
                case .partial(let node):
                    root = node
                case .finished(let node):
                    root = node
                }
            }
            guard !Task.isCancelled else { return }
            phase = .finished(.now)
        }
    }

    func cancel() {
        task?.cancel()
        if phase.isScanning { phase = .cancelled }
    }

    func open(_ node: StorageNode) {
        guard node.canDrillDown, !phase.isScanning || node.children.count > 0 else { return }
        pathIDs.append(node.id)
    }

    func goUp() { if !pathIDs.isEmpty { pathIDs.removeLast() } }

    func go(toDepth depth: Int) { pathIDs = Array(pathIDs.prefix(depth)) }

    func requestRemoval(_ nodes: [StorageNode]) {
        let eligible = nodes.filter { !$0.isAggregate }
        guard !eligible.isEmpty else { return }
        let entries = eligible.map {
            RemovalRequest.Entry(candidate: RemovalCandidate(url: $0.url, size: $0.size), name: $0.name,
                                 detail: Format.parentPath($0.url))
        }
        var request = RemovalRequest(kind: .storageExplorer, title: "Storage Explorer", entries: entries)
        request.onComplete = { [weak self] outcome in
            guard let self, var root = self.root else { return }
            let removed = Set(outcome.removed.map(\.originalPath))
            for node in eligible where removed.contains(node.url.path(percentEncoded: false)) {
                root = root.removing(node)
            }
            self.root = root
        }
        app.requestRemoval(request)
    }
}

#if DEBUG
extension StorageExplorerModel {
    func loadDemo() {
        rootURL = DemoData.home
        root = DemoData.storageTree
        pathIDs = []
        skippedProtected = false
        phase = .finished(.now)
    }
}
#endif
