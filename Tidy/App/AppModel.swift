import SwiftUI
import Observation

/// A request to remove user-chosen items, presented for review before anything happens.
struct RemovalRequest: Identifiable {
    struct Entry: Identifiable, Hashable {
        var id: URL { candidate.url }
        let candidate: RemovalCandidate
        let name: String
        let detail: String
        var warnings: [String] = []
    }

    let id = UUID()
    let kind: ActivityKind
    let title: String
    var entries: [Entry]
    /// Apps are always moved to the Trash so they can be recovered.
    var forceTrash = false
    var note: String?
    var onComplete: @MainActor (RemovalOutcome) -> Void = { _ in }

    var totalSize: Int64 { entries.reduce(0) { $0 + $1.candidate.size } }
}

@MainActor @Observable
final class AppModel {
    var selection: SidebarItem? = .dashboard
    let settings = AppSettings()
    let history = HistoryStore()
    let metrics = MetricsMonitor()

    private(set) var macInfo = SystemInfoService.macInfo()
    /// True while showing invented demo content (DEBUG builds only).
    private(set) var isDemo = false
    private(set) var volume = SystemInfoService.startupVolume()
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess

    private(set) var categories: [StorageCategory] = []
    private(set) var categoriesPhase: ScanPhase = .idle
    private var categoriesTask: Task<Void, Never>?

    // Long-lived feature models so results survive navigation.
    @ObservationIgnored private(set) lazy var cleanup = SmartCleanupModel(app: self)
    @ObservationIgnored private(set) lazy var explorer = StorageExplorerModel(app: self)
    @ObservationIgnored private(set) lazy var largeFiles = LargeFilesModel(app: self)
    @ObservationIgnored private(set) lazy var duplicates = DuplicatesModel(app: self)
    @ObservationIgnored private(set) lazy var downloads = DownloadsModel(app: self)
    @ObservationIgnored private(set) lazy var apps = AppManagerModel(app: self)
    @ObservationIgnored private(set) lazy var leftovers = LeftoversModel(app: self)

    var pendingRemoval: RemovalRequest?

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVolume() }
        }
        #if DEBUG
        if DemoData.isRequested { loadDemo() }
        #endif
    }

    var policy: SafetyPolicy { SafetyPolicy(userProtectedPaths: settings.protectedPaths) }

    func refreshVolume() {
        guard !isDemo else { return }
        volume = SystemInfoService.startupVolume()
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    func runningApps() -> RunningAppsSnapshot {
        let apps = NSWorkspace.shared.runningApplications
        return RunningAppsSnapshot(bundleIdentifiers: Set(apps.compactMap(\.bundleIdentifier)),
                                   names: Set(apps.compactMap { $0.localizedName?.lowercased() }))
    }

    // MARK: - Scan Mac

    var isScanningMac: Bool { cleanup.phase.isScanning || categoriesPhase.isScanning || leftovers.phase.isScanning }

    /// Runs the dashboard's combined scan: storage categories, Smart Cleanup, and app leftovers.
    func scanMac() {
        guard !isDemo else { return }
        cleanup.scan()
        leftovers.scan()
        measureCategories()
    }

    func cancelScanMac() {
        cleanup.cancel()
        leftovers.cancel()
        categoriesTask?.cancel()
        categoriesPhase = categories.isEmpty ? .idle : .cancelled
    }

    func measureCategories() {
        guard !isDemo else { return }
        refreshVolume()
        guard let volume else { return }
        categoriesTask?.cancel()
        categoriesPhase = .scanning(progress: nil, detail: "Measuring storage categories…")
        let fda = hasFullDiskAccess
        categoriesTask = Task {
            let result = await StorageAnalyzer.measureCategories(volume: volume, hasFullDiskAccess: fda) { _ in }
            guard !Task.isCancelled else { return }
            categories = result
            categoriesPhase = .finished(.now)
        }
    }

    // MARK: - Removal

    func requestRemoval(_ request: RemovalRequest) {
        guard !isDemo else { return }
        var request = request
        let policy = self.policy
        for index in request.entries.indices {
            request.entries[index].warnings = policy.warnings(for: request.entries[index].candidate.url)
        }
        pendingRemoval = request
    }

    func effectiveMode(for request: RemovalRequest) -> RemovalMode {
        request.forceTrash ? .moveToTrash : settings.removalMode
    }

    func perform(_ request: RemovalRequest) async -> RemovalOutcome {
        let mode = effectiveMode(for: request)
        let remover = FileRemover(policy: policy)
        let running = runningApps().bundleIdentifiers
        let candidates = request.entries.map(\.candidate)
        let outcome = await Task.detached(priority: .userInitiated) {
            await remover.remove(candidates, mode: mode, runningBundleIDs: running)
        }.value
        if settings.keepHistory {
            history.record(outcome, kind: request.kind, mode: mode, detail: request.title)
        }
        refreshVolume()
        request.onComplete(outcome)
        return outcome
    }

    func emptyTrash(knownSize: Int64?) async throws {
        try await TrashService.emptyWithFinder()
        if settings.keepHistory { history.recordTrashEmptied(bytes: knownSize ?? 0) }
        refreshVolume()
    }
}

#if DEBUG
extension AppModel {
    /// Replaces every model's content with invented data for screenshots. Nothing is scanned or written.
    func loadDemo() {
        isDemo = true
        macInfo = DemoData.macInfo
        volume = DemoData.volume
        hasFullDiskAccess = true
        categories = DemoData.categories
        categoriesPhase = .finished(.now)
        history.loadDemo()
        metrics.loadDemo()
        cleanup.loadDemo()
        explorer.loadDemo()
        largeFiles.loadDemo()
        duplicates.loadDemo()
        downloads.loadDemo()
        apps.loadDemo()
        leftovers.loadDemo()
    }
}
#endif
