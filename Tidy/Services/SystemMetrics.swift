import Foundation
import Darwin
import IOKit

struct CPUSample: Sendable {
    let user: Double
    let system: Double
    var total: Double { user + system }
}

enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    var explanation: String {
        switch self {
        case .normal: "Your Mac has enough memory."
        case .warning: "Memory is in high demand. Quitting unused apps may help."
        case .critical: "Memory is low. Quit apps you aren't using."
        }
    }
}

struct MemorySample: Sendable {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let free: UInt64
    let swapUsed: UInt64
    let pressure: MemoryPressure

    var used: UInt64 { app + wired + compressed }
    var available: UInt64 { total > used ? total - used : 0 }
}

struct DiskIOSample: Sendable {
    let bytesRead: UInt64
    let bytesWritten: UInt64
}

struct ProcessSample: Identifiable, Sendable, Hashable {
    let id: pid_t
    let name: String
    let path: String?
    let cpuPercent: Double
    let memory: UInt64
}

/// Reads system statistics using Mach, sysctl, IOKit, and libproc. Holds the
/// previous counters to compute deltas, so it is an actor.
actor SystemSampler {
    private let host = mach_host_self()
    private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastDisk: (DiskIOSample, Date)?
    private var lastProcessTimes: [pid_t: UInt64] = [:]
    private var lastProcessDate: Date?
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func cpu() -> CPUSample? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = (user: UInt64(load.cpu_ticks.0), system: UInt64(load.cpu_ticks.1),
                     idle: UInt64(load.cpu_ticks.2), nice: UInt64(load.cpu_ticks.3))
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return nil }
        let user = Double(ticks.user &- last.user + ticks.nice &- last.nice)
        let system = Double(ticks.system &- last.system)
        let idle = Double(ticks.idle &- last.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUSample(user: user / total, system: system / total)
    }

    func memory() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + purgeable) * page
        let free = UInt64(stats.free_count) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed: UInt64 = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)

        return MemorySample(total: ProcessInfo.processInfo.physicalMemory, app: app, wired: wired, compressed: compressed,
                            cached: cached, free: free, swapUsed: swapUsed,
                            pressure: MemoryPressure(rawValue: Int(level)) ?? .normal)
    }

    /// Returns read/write throughput in bytes per second across physical disks.
    func diskThroughput() -> (read: Double, write: Double)? {
        guard let current = Self.diskCounters() else { return nil }
        let now = Date.now
        defer { lastDisk = (current, now) }
        guard let (previous, date) = lastDisk else { return nil }
        let elapsed = now.timeIntervalSince(date)
        guard elapsed > 0 else { return nil }
        let read = Double(current.bytesRead &- previous.bytesRead) / elapsed
        let write = Double(current.bytesWritten &- previous.bytesWritten) / elapsed
        return (max(0, read), max(0, write))
    }

    private static func diskCounters() -> DiskIOSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return DiskIOSample(bytesRead: read, bytesWritten: written)
    }

    /// Samples processes that the current user can inspect. macOS doesn't expose
    /// other users' process statistics without elevated privileges.
    func processes(limit: Int) -> (top: [ProcessSample], inspected: Int, total: Int) {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        let now = Date.now
        let elapsedNs = lastProcessDate.map { now.timeIntervalSince($0) * 1_000_000_000 }
        var times: [pid_t: UInt64] = [:]
        var samples: [ProcessSample] = []
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }
            let cpuNs = UInt64(Double(usage.ri_user_time + usage.ri_system_time) * timebase)
            times[pid] = cpuNs
            var percent = 0.0
            if let elapsedNs, elapsedNs > 0, let previous = lastProcessTimes[pid], cpuNs >= previous {
                percent = Double(cpuNs - previous) / elapsedNs * 100
            }
            samples.append(ProcessSample(id: pid, name: Self.name(of: pid), path: Self.path(of: pid),
                                         cpuPercent: percent, memory: usage.ri_phys_footprint))
        }
        lastProcessTimes = times
        lastProcessDate = now
        let top = samples.sorted { ($0.cpuPercent, $0.memory) > ($1.cpuPercent, $1.memory) }.prefix(limit)
        return (Array(top), samples.count, count)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func name(of pid: pid_t) -> String {
        if let path = path(of: pid) {
            // Prefer the enclosing app's name for app executables.
            if let range = path.range(of: ".app/Contents/MacOS/") {
                let appPath = String(path[..<range.lowerBound])
                return (appPath as NSString).lastPathComponent
            }
            return (path as NSString).lastPathComponent
        }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
