import SwiftUI

/// The compact menu bar companion. Metrics are sampled only while it's open.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let metrics = app.metrics
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tidy").font(.headline)
                Spacer()
                Text(app.macInfo.modelName).font(.caption).foregroundStyle(.secondary)
            }
            if let volume = app.volume {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(volume.name, systemImage: "internaldrive")
                        Spacer()
                        Text("\(Format.bytes(volume.available)) available").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                    ProgressView(value: volume.utilization)
                        .tint(volume.utilization > 0.9 ? .red : .accentColor)
                        .accessibilityLabel("Storage \(Format.percent(volume.utilization)) used")
                    Text("\(Format.percent(volume.utilization)) used of \(Format.bytes(volume.total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label("CPU", systemImage: "cpu").foregroundStyle(.secondary)
                    Text(metrics.cpu.map { Format.percent($0.total) } ?? "—").monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Label("Memory Pressure", systemImage: "memorychip").foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        if let m = metrics.memory {
                            Circle().fill(m.pressure == .normal ? Color.green : m.pressure == .warning ? .yellow : .red)
                                .frame(width: 7, height: 7)
                            Text(m.pressure.title)
                        } else {
                            Text("—")
                        }
                    }
                }
                GridRow {
                    Label("Memory Used", systemImage: "chart.bar").foregroundStyle(.secondary)
                    Text(metrics.memory.map { "\(Format.memory($0.used)) of \(Format.memory($0.total))" } ?? "—").monospacedDigit()
                }
                GridRow {
                    Label("Last Cleanup", systemImage: "clock").foregroundStyle(.secondary)
                    Text(app.history.lastCleanup.map { "\(Format.bytes($0.bytes)), \(Format.relative($0.date))" } ?? "None yet")
                }
            }
            .font(.callout)
            Divider()
            HStack {
                Button("Quit Tidy") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Tidy") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .floatingProminentButtonStyle()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            app.refreshVolume()
            metrics.start("menubar")
        }
        .onDisappear { metrics.stop("menubar") }
    }
}
