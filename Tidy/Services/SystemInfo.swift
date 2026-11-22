import Foundation
import IOKit

struct MacInfo: Sendable {
    let modelName: String
    let modelIdentifier: String
    /// The hardware serial number, as shown in About This Mac. Nil if unavailable.
    let serialNumber: String?
    let osVersion: String
    let osBuild: String
    let processor: String
    let coreSummary: String
    /// Total core count, for example "8 Cores".
    let coreCount: String
    /// Performance/efficiency split, for example "4 Performance · 4 Efficiency". Nil on chips without one.
    let coreDetail: String?
    let memory: UInt64
    let computerName: String
}

struct VolumeInfo: Sendable, Equatable {
    let name: String
    let total: Int64
    /// Space available for important usage (includes purgeable space), matching Finder.
    let available: Int64
    /// Space that is free right now, excluding purgeable data.
    let free: Int64
    let format: String?

    var used: Int64 { max(0, total - available) }
    var purgeable: Int64 { max(0, available - free) }
    var utilization: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum SystemInfoService {
    static func macInfo() -> MacInfo {
        let identifier = sysctlString("hw.model") ?? "Mac"
        let processor = sysctlString("machdep.cpu.brand_string") ?? "Unknown processor"
        let performance = sysctlInt("hw.perflevel0.physicalcpu")
        let efficiency = sysctlInt("hw.perflevel1.physicalcpu")
        let total = sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount
        let cores: String
        if let p = performance, let e = efficiency, e > 0 {
            cores = "\(total) cores (\(p) performance, \(e) efficiency)"
        } else {
            cores = "\(total) cores"
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        return MacInfo(
            modelName: marketingModelName() ?? identifier,
            modelIdentifier: identifier,
            serialNumber: serialNumber(),
            osVersion: "macOS \(version)",
            osBuild: sysctlString("kern.osversion") ?? "",
            processor: processor,
            coreSummary: cores,
            coreCount: "\(total) Cores",
            coreDetail: performance.flatMap { p in efficiency.flatMap { e in e > 0 ? "\(p) Performance · \(e) Efficiency" : nil } },
            memory: ProcessInfo.processInfo.physicalMemory,
            computerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        )
    }

    /// Reads the hardware serial number from the platform expert, like About This Mac.
    private static func serialNumber() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Reads the marketing name (for example "MacBook Air (M2, 2022)") from the device tree.
    private static func marketingModelName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        return name.isEmpty ? nil : name
    }

    static func startupVolume() -> VolumeInfo? {
        volume(at: URL(filePath: "/"))
    }

    static func volume(at url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey, .volumeLocalizedNameKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeInfo(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total),
                          available: values.volumeAvailableCapacityForImportantUsage ?? free, free: free,
                          format: values.volumeLocalizedFormatDescription)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size { return Int(Int32(truncatingIfNeeded: value)) }
        return Int(value)
    }
}

// MARK: - Storage categories

struct StorageCategory: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable, CaseIterable {
        case applications, documents, photos, downloads, developer, library, systemAndOther, available
    }

    var id: Kind { kind }
    let kind: Kind
    let bytes: Int64
    /// True when the value is an estimate rather than a direct measurement.
    let isEstimate: Bool
    /// True when some folders couldn't be read, so the true value may be larger.
    let isPartial: Bool

    var title: String {
        switch kind {
        case .applications: "Applications"
        case .documents: "Documents"
        case .photos: "Photos & Pictures"
        case .downloads: "Downloads"
        case .developer: "Developer"
        case .library: "App Data & Caches"
        case .systemAndOther: "System Data & Other"
        case .available: "Available"
        }
    }

    var symbol: String {
        switch kind {
        case .applications: "app.badge"
        case .documents: "doc"
        case .photos: "photo"
        case .downloads: "arrow.down.circle"
        case .developer: "hammer"
        case .library: "tray.full"
        case .systemAndOther: "gearshape.2"
        case .available: "circle.dashed"
        }
    }

    var detail: String {
        switch kind {
        case .applications: "Apps in the Applications folders"
        case .documents: "Your Documents and Desktop folders"
        case .photos: ""
        case .downloads: "Your Downloads folder"
        case .developer: ""
        case .library: ""
        case .systemAndOther: "macOS, system data, and files outside the folders above. Estimated as used space minus measured categories."
        case .available: ""
        }
    }
}

enum StorageAnalyzer {
    /// Measures well-known folders. Each folder is read only with the access
    /// the user has granted; unreadable folders are reported as partial.
    static func measureCategories(volume: VolumeInfo, hasFullDiskAccess: Bool,
                                  progress: @escaping @Sendable (String) -> Void) async -> [StorageCategory] {
        let home = FileSystem.home
        let lib = FileSystem.library
        let containerSkips: Set<String> = hasFullDiskAccess ? [] : [
            lib.appending(path: "Containers").path(percentEncoded: false),
            lib.appending(path: "Group Containers").path(percentEncoded: false),
        ]
        let devPath = lib.appending(path: "Developer").path(percentEncoded: false)
        let plan: [(StorageCategory.Kind, [URL], Set<String>)] = [
            (.applications, [URL(filePath: "/Applications"), home.appending(path: "Applications")], []),
            (.documents, [home.appending(path: "Documents"), home.appending(path: "Desktop")], []),
            (.photos, [home.appending(path: "Pictures")], []),
            (.downloads, [home.appending(path: "Downloads")], []),
            (.developer, [lib.appending(path: "Developer")], []),
            (.library, [lib], containerSkips.union([devPath])),
        ]
        var results: [StorageCategory] = []
        await withTaskGroup(of: StorageCategory?.self) { group in
            for (kind, urls, skips) in plan {
                group.addTask {
                    var bytes: Int64 = 0
                    var partial = false
                    for url in urls where FileSystem.exists(url) {
                        if Task.isCancelled { return nil }
                        let usage = FileSystem.usage(of: url, skipping: skips)
                        bytes += usage.bytes
                        partial = partial || usage.inaccessible > 0 || !skips.isEmpty && kind == .library && !hasFullDiskAccess
                    }
                    progress(kind.rawValue)
                    return StorageCategory(kind: kind, bytes: bytes, isEstimate: false, isPartial: partial)
                }
            }
            for await result in group { if let result { results.append(result) } }
        }
        let measured = results.reduce(0) { $0 + $1.bytes }
        results.append(StorageCategory(kind: .systemAndOther, bytes: max(0, volume.used - measured), isEstimate: true, isPartial: false))
        let order = StorageCategory.Kind.allCases
        return results.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }
}
