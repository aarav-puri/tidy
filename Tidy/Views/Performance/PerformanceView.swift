import SwiftUI
import Charts

struct PerformanceView: View {
    @Environment(AppModel.self) private var app
    @State private var processSort = [KeyPathComparator(\ProcessSample.cpuPercent, order: .reverse)]

    private var metrics: MetricsMonitor { app.metrics }

    var body: some View {
        Form {
            cpuSection
            memorySection
            diskSection
            processSection
            Section {
                HStack {
                    Spacer()
                    Button("Open Activity Monitor") { Permissions.openSystemApp(bundleIdentifier: "com.apple.ActivityMonitor") }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Performance")
        .onAppear { metrics.start("performance", includeProcesses: true) }
        .onDisappear { metrics.stop("performance") }
    }

    private var cpuSection: some View {
        Section {
            MetricChart(points: metrics.cpuHistory, maxValue: 1, tint: .blue, format: { Format.percent($0) })
            LabeledContent("Current Usage", value: metrics.cpu.map { Format.percent($0.total) } ?? "Measuring…")
            if let cpu = metrics.cpu {
                LabeledContent("User", value: Format.percent(cpu.user))
                LabeledContent("System", value: Format.percent(cpu.system))
            }
            LabeledContent("Processor", value: "\(app.macInfo.processor), \(app.macInfo.coreSummary)")
        } header: {
            Text("CPU")
        }
    }

    private var memorySection: some View {
        Section {
            if let memory = metrics.memory {
                MetricChart(points: metrics.memoryHistory, maxValue: 1, tint: memory.pressure == .normal ? .green : (memory.pressure == .warning ? .yellow : .red),
                            format: { Format.percent($0) })
                VStack(alignment: .leading, spacing: 8) {
                    StorageBar(segments: [
                        .init(id: "app", title: "App Memory", bytes: Int64(memory.app), color: .blue),
                        .init(id: "wired", title: "Wired", bytes: Int64(memory.wired), color: .orange),
                        .init(id: "compressed", title: "Compressed", bytes: Int64(memory.compressed), color: .purple),
                        .init(id: "cached", title: "Cached Files", bytes: Int64(memory.cached), color: .gray, isEstimate: true),
                    ], total: Int64(memory.total), height: 14)
                    StorageLegend(segments: [
                        .init(id: "app", title: "App Memory", bytes: Int64(memory.app), color: .blue),
                        .init(id: "wired", title: "Wired", bytes: Int64(memory.wired), color: .orange),
                        .init(id: "compressed", title: "Compressed", bytes: Int64(memory.compressed), color: .purple),
                        .init(id: "cached", title: "Cached Files", bytes: Int64(memory.cached), color: .gray, isEstimate: true),
                    ])
                }
                .padding(.vertical, 4)
                LabeledContent("Memory Pressure") {
                    HStack(spacing: 6) {
                        Circle().fill(pressureColor(memory.pressure)).frame(width: 8, height: 8)
                        Text(memory.pressure.title)
                    }
                }
                LabeledContent("Physical Memory", value: Format.memory(memory.total))
                LabeledContent("Memory Used", value: Format.memory(memory.used))
                LabeledContent("Available", value: Format.memory(memory.available))
                LabeledContent("Swap Used", value: Format.memory(memory.swapUsed))
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Memory")
        }
    }

    private var diskSection: some View {
        Section {
            if let volume = app.volume {
                LabeledContent("Available", value: Format.bytes(volume.available))
                LabeledContent("Used", value: "\(Format.bytes(volume.used)) of \(Format.bytes(volume.total))")
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Read", systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary)
                    Text(Format.rate(metrics.diskRead)).monospacedDigit()
                    MetricChart(points: metrics.diskReadHistory, maxValue: nil, tint: .teal, height: 60, format: Format.rate)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Write", systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary)
                    Text(Format.rate(metrics.diskWrite)).monospacedDigit()
                    MetricChart(points: metrics.diskWriteHistory, maxValue: nil, tint: .indigo, height: 60, format: Format.rate)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Storage")
        }
    }

    private var processSection: some View {
        Section {
            if metrics.processes.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Process").gridColumnAlignment(.leading)
                        Text("CPU").gridColumnAlignment(.trailing)
                        Text("Memory").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(metrics.processes) { process in
                        GridRow {
                            HStack(spacing: 8) {
                                if let path = process.path, let range = path.range(of: ".app/") {
                                    FileIcon(url: URL(filePath: String(path[..<range.lowerBound]) + ".app"), size: 16)
                                } else {
                                    Image(systemName: "terminal").frame(width: 16).foregroundStyle(.secondary)
                                }
                                Text(process.name).lineLimit(1)
                            }
                            Text(String(format: "%.1f%%", process.cpuPercent)).monospacedDigit()
                            Text(Format.memory(process.memory)).monospacedDigit()
                        }
                    }
                }
            }
        } header: {
            Text("Most Active Processes")
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

/// A compact history chart for a single metric.
struct MetricChart: View {
    let points: [MetricPoint]
    let maxValue: Double?
    let tint: Color
    var height: CGFloat = 90
    let format: (Double) -> String

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Value", point.value))
                .foregroundStyle(tint.opacity(0.18))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(format(v)).font(.caption2) } }
            }
        }
        .chartYScale(domain: 0...(maxValue ?? max(points.map(\.value).max() ?? 1, 1)))
        .frame(height: height)
        .accessibilityLabel("History chart")
        .accessibilityValue(points.last.map { format($0.value) } ?? "No data")
    }
}
