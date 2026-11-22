import Foundation
import CoreServices

/// Low-level, thread-safe file system helpers built on POSIX and Foundation APIs.
enum FileSystem {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let library = home.appending(path: "Library", directoryHint: .isDirectory)

    struct Usage: Sendable {
        var bytes: Int64 = 0
        var files: Int = 0
        var inaccessible: Int = 0
        var newestModification: Date?
    }

    /// Lightweight `lstat` result.
    struct Info: Sendable {
        let isDirectory: Bool
        let isSymlink: Bool
        let size: Int64
        let allocated: Int64
        let modified: Date
        let accessed: Date
        let owner: uid_t
        let flags: UInt32
        let device: Int32
        let inode: UInt64
        let links: UInt16
    }

    static func info(_ url: URL) -> Info? {
        var st = stat()
        guard lstat(url.path(percentEncoded: false), &st) == 0 else { return nil }
        return Info(st)
    }

    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path(percentEncoded: false), &st) == 0
    }

    /// Lists the immediate children of a directory, including hidden items.
    /// Returns `nil` when the directory cannot be read (permissions, TCC, or missing).
    static func children(of url: URL) -> [URL]? {
        guard let dir = opendir(url.path(percentEncoded: false)) else { return nil }
        defer { closedir(dir) }
        var result: [URL] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let isDir = entry.pointee.d_type == DT_DIR
            result.append(url.appending(path: name, directoryHint: isDir ? .isDirectory : .notDirectory))
        }
        return result
    }

    static func isReadableDirectory(_ url: URL) -> Bool {
        guard let dir = opendir(url.path(percentEncoded: false)) else { return false }
        closedir(dir)
        return true
    }

    /// Measures allocated (on-disk) size of a file or directory tree using `fts`.
    /// Hard-linked files are counted once. Does not cross volume boundaries and never follows symlinks.
    static func usage(of url: URL, skipping skip: Set<String> = [], isCancelled: () -> Bool = { Task.isCancelled }) -> Usage {
        var usage = Usage()
        let path = url.path(percentEncoded: false)
        guard let cPath = strdup(path) else { return usage }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            usage.inaccessible = 1
            return usage
        }
        defer { fts_close(fts) }
        var seenInodes = Set<UInt64>()
        var counter = 0
        while let entry = fts_read(fts) {
            counter += 1
            if counter & 0x3FF == 0, isCancelled() { break }
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D:
                if !skip.isEmpty {
                    let p = String(cString: entry.pointee.fts_path)
                    if skip.contains(p) { fts_set(fts, entry, FTS_SKIP) }
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = entry.pointee.fts_statp?.pointee else { continue }
                if st.st_nlink > 1, info == FTS_F {
                    if !seenInodes.insert(UInt64(st.st_ino)).inserted { continue }
                }
                usage.bytes += Int64(st.st_blocks) * 512
                usage.files += 1
                let modified = Date(timespec: st.st_mtimespec)
                if usage.newestModification.map({ modified > $0 }) ?? true { usage.newestModification = modified }
            case FTS_DP:
                if let st = entry.pointee.fts_statp?.pointee { usage.bytes += Int64(st.st_blocks) * 512 }
            case FTS_DNR, FTS_ERR, FTS_NS:
                usage.inaccessible += 1
            default:
                break
            }
        }
        return usage
    }

    /// Returns the canonical path of a URL without resolving the final component,
    /// so a symlink is evaluated as itself rather than its target.
    static func canonicalPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().path(percentEncoded: false)
        let name = standardized.lastPathComponent
        guard let resolved = realpath(parent, nil) else { return standardized.path(percentEncoded: false) }
        defer { free(resolved) }
        let parentPath = String(cString: resolved)
        if name.isEmpty || name == "/" { return parentPath }
        return parentPath == "/" ? "/" + name : parentPath + "/" + name
    }

    /// Reads `kMDItemWhereFroms` (download source) from extended attributes.
    static func whereFroms(_ url: URL) -> [String] {
        let path = url.path(percentEncoded: false)
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return [] }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW) }
        guard read == length,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { return [] }
        return list.filter { !$0.isEmpty }
    }

    /// Last-opened date as recorded by Spotlight. Returns nil when unknown;
    /// callers must treat nil as "unknown", never as "unused".
    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func dateAdded(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
    }
}

extension FileSystem.Info {
    init(_ st: stat) {
        let mode = st.st_mode & S_IFMT
        isDirectory = mode == S_IFDIR
        isSymlink = mode == S_IFLNK
        size = Int64(st.st_size)
        allocated = Int64(st.st_blocks) * 512
        modified = Date(timespec: st.st_mtimespec)
        accessed = Date(timespec: st.st_atimespec)
        owner = st.st_uid
        flags = st.st_flags
        device = st.st_dev
        inode = UInt64(st.st_ino)
        links = st.st_nlink
    }

    /// SIP-protected (`SF_RESTRICTED`) or immutable (`uchg`/`schg`).
    var isSystemProtected: Bool {
        let sfRestricted: UInt32 = 0x0008_0000
        let sfImmutable: UInt32 = 0x0002_0000
        let ufImmutable: UInt32 = 0x0000_0002
        return flags & (sfRestricted | sfImmutable | ufImmutable) != 0
    }
}

extension Date {
    init(timespec ts: timespec) {
        self.init(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000)
    }
}
