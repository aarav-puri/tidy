import Foundation
import Observation

struct MetricPoint: Identifiable, Sendable {
    let id: Int
    let date: Date
    let value: Double
}

/// Samples system metrics only while at least one view is displaying them,
/// at a modest interval, so Tidy stays lightweight in the background.
@MainActor @Observable
final class MetricsMonitor {
    private(set) var cpu: CPUSample?
    private(set) var memory: MemorySample?
    private(set) var diskRead: Double = 0
    private(set) var diskWrite: Double = 0
    private(set) var cpuHistory: [MetricPoint] = []
    private(set) var memoryHistory: [MetricPoint] = []
    private(set) var diskReadHistory: [MetricPoint] = []
    private(set) var diskWriteHistory: [MetricPoint] = []
    private(set) var processes: [ProcessSample] = []
    private(set) var processesInspected = 0
    private(set) var processesTotal = 0

    @ObservationIgnored private let sampler = SystemSampler()
    @ObservationIgnored private var consumers: [String: Bool] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var isDemo = false
    private let historyLength = 90
    private let interval: Duration = .seconds(2)

    /// Starts sampling on behalf of `consumer`. Process sampling is more costly
    /// and only runs when a consumer asks for it.
    func start(_ consumer: String, includeProcesses: Bool = false) {
        guard !isDemo else { return }
        consumers[consumer] = includeProcesses
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
            }
        }
    }

    func stop(_ consumer: String) {
        consumers[consumer] = nil
        if consumers.isEmpty {
            loop?.cancel()
            loop = nil
        }
    }

    private func sample() async {
        let wantsProcesses = consumers.values.contains(true)
        async let cpuSample = sampler.cpu()
        async let memorySample = sampler.memory()
        async let disk = sampler.diskThroughput()
        let (c, m, d) = await (cpuSample, memorySample, disk)
        let now = Date.now
        tick += 1
        if let c {
            cpu = c
            append(&cpuHistory, c.total, now)
        }
        if let m {
            memory = m
            append(&memoryHistory, Double(m.used) / Double(max(m.total, 1)), now)
        }
        if let d {
            diskRead = d.read
            diskWrite = d.write
            append(&diskReadHistory, d.read, now)
            append(&diskWriteHistory, d.write, now)
        }
        if wantsProcesses {
            let result = await sampler.processes(limit: 12)
            processes = result.top
            processesInspected = result.inspected
            processesTotal = result.total
        }
    }

    private func append(_ series: inout [MetricPoint], _ value: Double, _ date: Date) {
        series.append(MetricPoint(id: tick, date: date, value: value))
        if series.count > historyLength { series.removeFirst(series.count - historyLength) }
    }
}

#if DEBUG
extension MetricsMonitor {
    func loadDemo() {
        isDemo = true
        let count = historyLength
        let start = Date.now.addingTimeInterval(-Double(count) * 2)
        func points(_ values: [Double]) -> [MetricPoint] {
            values.enumerated().map { MetricPoint(id: $0.offset, date: start.addingTimeInterval(Double($0.offset) * 2), value: $0.element) }
        }
        let cpuValues = DemoData.series(count, base: 0.24, swing: 0.14, seed: 0.4)
        cpuHistory = points(cpuValues)
        cpu = CPUSample(user: (cpuValues.last ?? 0.2) * 0.68, system: (cpuValues.last ?? 0.2) * 0.32)
        memory = DemoData.memory
        let used = Double(DemoData.memory.used) / Double(DemoData.memory.total)
        memoryHistory = points(DemoData.series(count, base: used, swing: 0.025, seed: 1.7))
        let reads = DemoData.series(count, base: 18_000_000, swing: 16_000_000, seed: 2.1)
        let writes = DemoData.series(count, base: 9_000_000, swing: 8_000_000, seed: 3.3)
        diskReadHistory = points(reads)
        diskWriteHistory = points(writes)
        diskRead = reads.last ?? 0
        diskWrite = writes.last ?? 0
        processes = DemoData.processes
        processesInspected = 412
        processesTotal = 486
        tick = count
    }
}
#endif
