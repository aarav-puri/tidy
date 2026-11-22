import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HeroCard()
                InsightTiles()
                HStack(alignment: .top, spacing: 18) {
                    MacCard(info: app.macInfo)
                    ActivityCard()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .glassGroup(spacing: 24)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if app.isScanningMac {
                    Button("Stop Scan", systemImage: "stop.fill") { app.cancelScanMac() }
                } else {
                    Button("Scan Mac", systemImage: "magnifyingglass") { app.scanMac() }
                        .help("Scan Mac")
                }
            }
        }
        .onAppear { app.refreshVolume() }
    }
}

// MARK: - Cards

/// A Liquid Glass panel. Its content sits on top of the glass.
private struct GlassCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), clear: true)
    }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GlassCard(padding: 26) {
            if let volume = app.volume {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 30) {
                        StorageRing(fraction: volume.utilization)
                            .frame(width: 150, height: 150)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(volume.name, systemImage: "internaldrive")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            GlassText(Format.bytes(volume.available), size: 56)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            (Text("available of \(Format.bytes(volume.total))  ·  ")
                                + Text("\(Format.percent(volume.utilization)) used")
                                    .foregroundStyle(volume.utilization > 0.9 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            actions.padding(.top, 14)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StorageBar(segments: segments(volume), total: volume.total, height: 12)
                            .clipShape(Capsule())
                        HStack(alignment: .firstTextBaseline) {
                            StorageLegend(segments: segments(volume))
                            Spacer()
                            footnote
                        }
                    }
                }
            } else {
                Text("Storage information isn't available.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if app.isScanningMac, case .scanning(let progress, let detail) = app.cleanup.phase {
            ScanStatusView(title: "Scanning Your Mac…", detail: detail, progress: progress) { app.cancelScanMac() }
                .frame(maxWidth: 380)
        } else {
            HStack(spacing: 10) {
                Button {
                    app.scanMac()
                } label: {
                    Label("Scan Mac", systemImage: "sparkle.magnifyingglass").padding(.horizontal, 6)
                }
                .floatingProminentButtonStyle()
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: [.command, .option])
                if app.categoriesPhase == .idle {
                    Button("Measure Categories") { app.measureCategories() }
                        .glassButtonStyle()
                        .controlSize(.large)
                }
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if app.categoriesPhase.isScanning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Measuring…")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func segments(_ volume: VolumeInfo) -> [StorageBar.Segment] {
        if app.categories.isEmpty {
            return [StorageBar.Segment(id: "used", title: "Used", bytes: volume.used, color: .accentColor)]
        }
        return app.categories.filter { $0.kind != .available }.map {
            StorageBar.Segment(id: $0.kind.rawValue, title: $0.title, bytes: $0.bytes, color: $0.kind.color, isEstimate: $0.isEstimate)
        }
    }
}

/// A luminous ring showing how full the disk is.
private struct StorageRing: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var shown: Double = 0

    private var tint: [Color] {
        if fraction > 0.9 { return [Color.red.opacity(0.75), .red] }
        return [AmbientBackdrop.iconBlue.opacity(0.55), AmbientBackdrop.iconBlue]
    }

    var body: some View {
        ZStack {
            Circle().stroke((scheme == .dark ? Color.white : Color.black).opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: tint, center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (tint.last ?? .blue).opacity(0.35), radius: 6)
            Image(nsImage: NSWorkspace.shared.icon(forFile: "/"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .padding(7)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 1.1)) { shown = fraction }
        }
        .onChange(of: fraction) { _, new in shown = new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk \(Format.percent(fraction)) used")
    }
}

private struct InsightTiles: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 18) {
            InsightTile(title: "Smart Cleanup", symbol: "eraser", tint: .teal, destination: .smartCleanup,
                        value: app.cleanup.hasResults ? Format.bytes(app.cleanup.reclaimable) : nil,
                        detail: app.cleanup.hasResults
                            ? "\(Format.count(app.cleanup.candidateCount, singular: "item")) to review"
                            : nil)
            InsightTile(title: "App Leftovers", symbol: "puzzlepiece.extension", tint: .orange, destination: .leftovers,
                        value: app.leftovers.phase.hasResults ? Format.bytes(app.leftovers.totalSize) : nil,
                        detail: app.leftovers.phase.hasResults
                            ? "From \(Format.count(app.leftovers.groups.count, singular: "app"))"
                            : nil)
            InsightTile(title: "Duplicates", symbol: "square.on.square", tint: .indigo, destination: .duplicates,
                        value: app.duplicates.phase.hasResults ? Format.bytes(app.duplicates.wastedSpace) : nil,
                        detail: app.duplicates.phase.hasResults
                            ? "In \(Format.count(app.duplicates.groups.count, singular: "group"))"
                            : nil)
        }
    }
}

private struct InsightTile: View {
    @Environment(AppModel.self) private var app
    let title: String
    let symbol: String
    let tint: Color
    let destination: SidebarItem
    let value: String?
    let detail: String?

    var body: some View {
        Button {
            app.selection = destination
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AmbientBackdrop.iconBlue)
                        .frame(width: 34, height: 34)
                        .background(AmbientBackdrop.iconBlue.opacity(0.14), in: Circle())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    if let value {
                        GlassText(value, size: 30)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        GlassText("Not scanned", size: 22, weight: .medium)
                            .frame(height: 36, alignment: .leading)
                    }
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true, clear: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(destination.title)")
    }
}

private struct MacCard: View {
    let info: MacInfo

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: info.modelName.localizedCaseInsensitiveContains("MacBook") ? "laptopcomputer" : "desktopcomputer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AmbientBackdrop.iconBlue)
                        .frame(width: 44, height: 44)
                        .background(AmbientBackdrop.iconBlue.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.modelName).font(.headline)
                        Text("\(info.osVersion) (\(info.osBuild))").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .topLeading, horizontalSpacing: 22, verticalSpacing: 14) {
                    GridRow {
                        Stat(title: "Chip", value: info.processor)
                        Stat(title: "Memory", value: Format.memory(info.memory))
                    }
                    GridRow {
                        Stat(title: "CPU", value: info.coreCount, detail: info.coreDetail)
                        Stat(title: "Serial Number", value: info.serialNumber ?? "Unavailable")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct Stat: View {
        let title: String
        let value: String
        var detail: String? = nil

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ActivityCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent Activity").font(.headline)
                    Spacer()
                    if !app.history.entries.isEmpty {
                        Button("Show All") { app.selection = .history }
                            .buttonStyle(.link)
                    }
                }
                if app.history.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        GlassText("0 KB", size: 26)
                        Text("reclaimed in total").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        GlassText(Format.bytes(app.history.totalReclaimed), size: 26)
                        Text("reclaimed in total").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(app.history.entries.prefix(3)) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
    }
}
