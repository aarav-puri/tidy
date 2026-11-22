import Foundation
import Synchronization

/// An immutable node in a measured directory tree. Small subtrees are collapsed
/// so memory stays bounded on very large disks.
final class StorageNode: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let size: Int64
    let itemCount: Int
    let modified: Date?
    let inaccessibleCount: Int
    /// Aggregates entries that were too small to keep individually.
    let isAggregate: Bool
    let children: [StorageNode]

    init(name: String, url: URL, isDirectory: Bool, isPackage: Bool = false, size: Int64, itemCount: Int,
         modified: Date?, inaccessibleCount: Int = 0, isAggregate: Bool = false, children: [StorageNode] = []) {
        self.id = isAggregate ? url.path(percentEncoded: false) + "/\u{0}other" : url.path(percentEncoded: false)
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.size = size
        self.itemCount = itemCount
        self.modified = modified
        self.inaccessibleCount = inaccessibleCount
        self.isAggregate = isAggregate
        self.children = children
    }

    var canDrillDown: Bool { isDirectory && !isPackage && !isAggregate && !children.isEmpty }

    static func == (lhs: StorageNode, rhs: StorageNode) -> Bool { lhs.id == rhs.id && lhs.size == rhs.size }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Returns a copy of this tree with `target` removed and ancestor sizes updated.
    func removing(_ target: StorageNode) -> StorageNode {
        guard target.id.hasPrefix(id + "/") || id == "/" else { return self }
        var newChildren: [StorageNode] = []
        var removedSize: Int64 = 0
        var removedCount = 0
        for child in children {
            if child.id == target.id {
                removedSize = child.size
                removedCount = child.itemCount
                continue
            }
            let updated = child.removing(target)
            removedSize += child.size - updated.size
            removedCount += child.itemCount - updated.itemCount
            newChildren.append(updated)
        }
        guard removedSize != 0 || removedCount != 0 || newChildren.count != children.count else { return self }
        return StorageNode(name: name, url: url, isDirectory: isDirectory, isPackage: isPackage, size: size - removedSize,
                           itemCount: itemCount - removedCount, modified: modified, inaccessibleCount: inaccessibleCount,
                           children: newChildren)
    }
}

enum StorageTreeEvent: Sendable {
    case progress(items: Int, bytes: Int64, current: String)
    /// A partial root, emitted as top-level folders finish measuring.
    case partial(StorageNode)
    case finished(StorageNode)
}

/// Recursively measures a folder. Top-level children are measured in parallel and
/// streamed as they complete so the interface fills in progressively.
struct StorageTreeScanner: Sendable {
    let root: URL
    let skipPaths: Set<String>
    /// Children smaller than this are folded into an aggregate node.
    var keepThreshold: Int64 = 1_000_000
    var maxChildrenPerFolder = 150

    private final class Counter: Sendable {
        let items = Atomic<Int>(0)
        let bytes = Atomic<Int64>(0)
    }

    func scan() -> AsyncStream<StorageTreeEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let counter = Counter()
                let rootInfo = FileSystem.info(root)
                guard let entries = FileSystem.children(of: root) else {
                    continuation.yield(.finished(StorageNode(name: root.lastPathComponent, url: root, isDirectory: true,
                                                             size: 0, itemCount: 0, modified: rootInfo?.modified,
                                                             inaccessibleCount: 1)))
                    continuation.finish()
                    return
                }
                // Progress ticker.
                let ticker = Task.detached {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        continuation.yield(.progress(items: counter.items.load(ordering: .relaxed),
                                                     bytes: counter.bytes.load(ordering: .relaxed), current: ""))
                    }
                }
                var finished: [StorageNode] = []
                await withTaskGroup(of: StorageNode?.self) { group in
                    var iterator = entries.makeIterator()
                    func addNext() -> Bool {
                        guard let next = iterator.next() else { return false }
                        group.addTask { self.measure(next, counter: counter, depth: 1) }
                        return true
                    }
                    for _ in 0..<6 { if !addNext() { break } }
                    for await node in group {
                        if let node { finished.append(node) }
                        if Task.isCancelled { group.cancelAll(); break }
                        continuation.yield(.partial(self.assemble(root, info: rootInfo, children: finished)))
                        _ = addNext()
                    }
                }
                ticker.cancel()
                continuation.yield(.finished(self.assemble(root, info: rootInfo, children: finished)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func assemble(_ url: URL, info: FileSystem.Info?, children: [StorageNode]) -> StorageNode {
        let (kept, size, count, inaccessible) = prune(children)
        return StorageNode(name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, url: url, isDirectory: true,
                           size: size + (info?.allocated ?? 0), itemCount: count, modified: info?.modified,
                           inaccessibleCount: inaccessible, children: kept)
    }

    private func prune(_ children: [StorageNode]) -> ([StorageNode], Int64, Int, Int) {
        let sorted = children.sorted { $0.size > $1.size }
        var kept: [StorageNode] = []
        var otherSize: Int64 = 0, otherCount = 0
        var total: Int64 = 0, count = 0, inaccessible = 0
        for child in sorted {
            total += child.size
            count += child.itemCount
            inaccessible += child.inaccessibleCount
            if kept.count < maxChildrenPerFolder && (child.size >= keepThreshold || kept.count < 12) {
                kept.append(child)
            } else {
                otherSize += child.size
                otherCount += child.itemCount
            }
        }
        if otherCount > 0, let parent = children.first?.url.deletingLastPathComponent() {
            kept.append(StorageNode(name: "\(otherCount.formatted()) smaller items", url: parent, isDirectory: false,
                                    size: otherSize, itemCount: otherCount, modified: nil, isAggregate: true))
        }
        return (kept, total, count, inaccessible)
    }

    private func measure(_ url: URL, counter: Counter, depth: Int) -> StorageNode? {
        if Task.isCancelled { return nil }
        let path = url.path(percentEncoded: false)
        if skipPaths.contains(path) {
            return StorageNode(name: url.lastPathComponent, url: url, isDirectory: true, size: 0, itemCount: 0,
                               modified: nil, inaccessibleCount: 1)
        }
        guard let info = FileSystem.info(url) else { return nil }
        if !info.isDirectory {
            counter.items.add(1, ordering: .relaxed)
            counter.bytes.add(info.allocated, ordering: .relaxed)
            return StorageNode(name: url.lastPathComponent, url: url, isDirectory: false, size: info.allocated,
                               itemCount: 1, modified: info.modified)
        }
        let isPackage = Packages.isPackage(url.lastPathComponent)
        if isPackage {
            let usage = FileSystem.usage(of: url, skipping: skipPaths)
            counter.items.add(usage.files, ordering: .relaxed)
            counter.bytes.add(usage.bytes, ordering: .relaxed)
            return StorageNode(name: url.lastPathComponent, url: url, isDirectory: true, isPackage: true, size: usage.bytes,
                               itemCount: usage.files, modified: info.modified, inaccessibleCount: usage.inaccessible)
        }
        guard let entries = FileSystem.children(of: url) else {
            return StorageNode(name: url.lastPathComponent, url: url, isDirectory: true, size: info.allocated, itemCount: 0,
                               modified: info.modified, inaccessibleCount: 1)
        }
        var children: [StorageNode] = []
        children.reserveCapacity(entries.count)
        for entry in entries {
            if Task.isCancelled { return nil }
            if let node = measure(entry, counter: counter, depth: depth + 1) { children.append(node) }
        }
        let (kept, size, count, inaccessible) = prune(children)
        // Collapse small folders entirely to bound memory.
        let finalChildren = size < keepThreshold ? [] : kept
        return StorageNode(name: url.lastPathComponent, url: url, isDirectory: true, size: size + info.allocated,
                           itemCount: count, modified: info.modified, inaccessibleCount: inaccessible, children: finalChildren)
    }
}
