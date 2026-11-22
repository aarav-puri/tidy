import Foundation
import CryptoKit

struct FoundFile: Identifiable, Sendable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let modified: Date
    let kind: FileKind
    let device: Int32
    let inode: UInt64
    var lastOpened: Date?

    var name: String { url.lastPathComponent }
    var location: String { Format.parentPath(url) }
}

/// Walks folders for individual files, never descending into packages
/// (apps, Photos libraries, bundles), hidden folders, or excluded locations.
struct FileWalker: Sendable {
    let roots: [URL]
    let excluded: Set<String>
    let minimumSize: Int64
    /// Folder names that are never useful to search and are often huge.
    static let skippedFolderNames: Set<String> = [".git", "node_modules", ".Trash", "DerivedData", ".build", "Pods"]

    func walk(onProgress: (Int, String) -> Void, onFile: (FoundFile) -> Void) {
        var visited = 0
        var seenInodes = Set<String>()
        for root in roots {
            let path = root.path(percentEncoded: false)
            guard let cPath = strdup(path) else { continue }
            defer { free(cPath) }
            var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
            guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(fts) }
            while let entry = fts_read(fts) {
                if Task.isCancelled { return }
                visited += 1
                let info = Int32(entry.pointee.fts_info)
                if info == FTS_D {
                    let entryPath = String(cString: entry.pointee.fts_path)
                    let name = (entryPath as NSString).lastPathComponent
                    if entry.pointee.fts_level > 0,
                       name.hasPrefix(".") || Self.skippedFolderNames.contains(name) || Packages.isPackage(name)
                        || excluded.contains(entryPath) || (entryPath as NSString).lastPathComponent == "Library" && entry.pointee.fts_level == 1 && root == FileSystem.home {
                        fts_set(fts, entry, FTS_SKIP)
                        continue
                    }
                    if visited % 200 == 0 { onProgress(visited, entryPath) }
                    continue
                }
                guard info == FTS_F, let st = entry.pointee.fts_statp?.pointee else { continue }
                let size = Int64(st.st_size)
                guard size >= minimumSize else { continue }
                let entryPath = String(cString: entry.pointee.fts_path)
                let name = (entryPath as NSString).lastPathComponent
                if name.hasPrefix(".") { continue }
                if st.st_nlink > 1, !seenInodes.insert("\(st.st_dev):\(st.st_ino)").inserted { continue }
                let url = URL(filePath: entryPath, directoryHint: .notDirectory)
                onFile(FoundFile(url: url, size: size, modified: Date(timespec: st.st_mtimespec), kind: FileKind.classify(url),
                                 device: st.st_dev, inode: UInt64(st.st_ino)))
            }
        }
        onProgress(visited, "")
    }
}

// MARK: - Large files

enum LargeFileEvent: Sendable {
    case progress(visited: Int, current: String)
    case found([FoundFile])
    case finished
}

struct LargeFileScanner: Sendable {
    let walker: FileWalker

    func scan() -> AsyncStream<LargeFileEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var batch: [FoundFile] = []
                walker.walk(onProgress: { visited, current in
                    continuation.yield(.progress(visited: visited, current: current))
                    if !batch.isEmpty { continuation.yield(.found(batch)); batch.removeAll() }
                }, onFile: { file in
                    var file = file
                    file.lastOpened = FileSystem.lastUsedDate(file.url)
                    batch.append(file)
                })
                if !batch.isEmpty { continuation.yield(.found(batch)) }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Duplicates

struct DuplicateGroup: Identifiable, Sendable, Hashable {
    let id: String
    let size: Int64
    let kind: FileKind
    var files: [FoundFile]

    var wastedSpace: Int64 { size * Int64(max(0, files.count - 1)) }
}

enum DuplicateEvent: Sendable {
    case stage(String, Double?)
    case groups([DuplicateGroup])
    case finished(filesExamined: Int, bytesHashed: Int64)
}

/// Byte-identical duplicate detection in three stages:
/// 1. group by exact size, 2. compare a fingerprint of the first and last 64 KB,
/// 3. confirm with a full SHA-256 of the entire contents.
struct DuplicateFinder: Sendable {
    let walker: FileWalker

    func scan() -> AsyncStream<DuplicateEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                // Stage 1: size buckets.
                var bySize: [Int64: [FoundFile]] = [:]
                var examined = 0
                walker.walk(onProgress: { visited, _ in
                    continuation.yield(.stage("Looking for files with matching sizes… \(visited.formatted()) items checked", nil))
                }, onFile: { file in
                    examined += 1
                    bySize[file.size, default: []].append(file)
                })
                if Task.isCancelled { continuation.finish(); return }
                let sizeGroups = bySize.values.filter { $0.count > 1 }

                // Stage 2: partial fingerprints.
                continuation.yield(.stage("Comparing file fingerprints…", 0))
                var candidates: [[FoundFile]] = []
                for (index, group) in sizeGroups.enumerated() {
                    if Task.isCancelled { continuation.finish(); return }
                    var byPrefix: [Data: [FoundFile]] = [:]
                    for file in group {
                        if let fp = Self.fingerprint(file.url, size: file.size) { byPrefix[fp, default: []].append(file) }
                    }
                    candidates.append(contentsOf: byPrefix.values.filter { $0.count > 1 })
                    if index % 20 == 0 {
                        continuation.yield(.stage("Comparing file fingerprints…", Double(index) / Double(max(sizeGroups.count, 1)) * 0.2))
                    }
                }

                // Stage 3: full content hash.
                let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + $1.size } }
                var hashed: Int64 = 0
                var emitted: [DuplicateGroup] = []
                for group in candidates.sorted(by: { $0[0].size > $1[0].size }) {
                    if Task.isCancelled { break }
                    var byHash: [String: [FoundFile]] = [:]
                    for file in group {
                        if Task.isCancelled { break }
                        if let digest = Self.sha256(file.url) { byHash[digest, default: []].append(file) }
                        hashed += file.size
                        let fraction = totalBytes > 0 ? Double(hashed) / Double(totalBytes) : 1
                        continuation.yield(.stage("Verifying contents… \(Format.bytes(hashed)) of \(Format.bytes(totalBytes))", 0.2 + 0.8 * fraction))
                    }
                    let confirmed = byHash.compactMap { digest, files -> DuplicateGroup? in
                        guard files.count > 1 else { return nil }
                        let sorted = files.sorted { $0.modified < $1.modified }
                        return DuplicateGroup(id: digest, size: sorted[0].size, kind: sorted[0].kind, files: sorted)
                    }
                    if !confirmed.isEmpty {
                        emitted.append(contentsOf: confirmed)
                        continuation.yield(.groups(confirmed))
                    }
                }
                continuation.yield(.finished(filesExamined: examined, bytesHashed: hashed))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static let chunk = 64 * 1024

    static func fingerprint(_ url: URL, size: Int64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        hasher.update(data: head)
        if size > Int64(chunk * 2) {
            try? handle.seek(toOffset: UInt64(size) - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return Data(hasher.finalize())
    }

    static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let data: Data? = autoreleasepool { try? handle.read(upToCount: 1 << 20) }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Downloads

struct DownloadItem: Identifiable, Sendable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let isFolder: Bool
    let added: Date?
    let modified: Date
    let kind: FileKind
    let kindDescription: String
    let source: String?

    var name: String { url.lastPathComponent }
}

enum DownloadsScanner {
    static var folder: URL { FileSystem.home.appending(path: "Downloads", directoryHint: .isDirectory) }

    static func scan() async -> Result<[DownloadItem], TidyError> {
        await Task.detached(priority: .userInitiated) {
            guard let children = FileSystem.children(of: folder) else {
                return .failure(.permissionDenied("Downloads"))
            }
            var items: [DownloadItem] = []
            for url in children where !url.lastPathComponent.hasPrefix(".") {
                if Task.isCancelled { break }
                guard let info = FileSystem.info(url) else { continue }
                let size = info.isDirectory ? FileSystem.usage(of: url).bytes : info.allocated
                let source = FileSystem.whereFroms(url).first.flatMap { URL(string: $0)?.host() }
                items.append(DownloadItem(url: url, size: size, isFolder: info.isDirectory && !Packages.isPackage(url.lastPathComponent),
                                          added: FileSystem.dateAdded(url), modified: info.modified,
                                          kind: FileKind.classify(url), kindDescription: info.isDirectory && url.pathExtension.isEmpty ? "Folder" : FileKind.kindDescription(for: url),
                                          source: source))
            }
            return .success(items.sorted { $0.size > $1.size })
        }.value
    }
}
