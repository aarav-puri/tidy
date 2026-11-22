import SwiftUI
import QuickLook
import Charts

struct StorageExplorerView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Set<StorageNode.ID> = []
    @State private var sortOrder = [KeyPathComparator(\StorageNode.size, order: .reverse)]
    @State private var previewURL: URL?
    @State private var choosingFolder = false

    private var model: StorageExplorerModel { app.explorer }

    var body: some View {
        Group {
            if model.root == nil && !model.phase.isScanning {
                IntroView(title: "Storage Explorer", symbol: "chart.pie",
                          message: "See which folders take up the most space.") {
                    Button("Scan Home Folder") { model.scan(FileSystem.home) }
                        .floatingProminentButtonStyle()
                        .controlSize(.large)
                    Button("Choose Folder…") { choosingFolder = true }
                }
            } else {
                content
            }
        }
        .navigationTitle("Storage Explorer")
        .navigationSubtitle(model.root == nil ? "" : Format.path(model.rootURL))
        .toolbar { toolbar }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.scan(url) }
        }
        .quickLookPreview($previewURL)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") { model.goUp(); selection = [] }
                .disabled(model.pathIDs.isEmpty)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Go to the enclosing folder")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu("Location", systemImage: "folder") {
                Button("Home Folder") { model.scan(FileSystem.home) }
                Button("Startup Disk") { model.scan(URL(filePath: "/")) }
                Divider()
                Button("Choose Folder…") { choosingFolder = true }
            }
            .help("Choose what to explore")
            if model.phase.isScanning {
                Button("Stop", systemImage: "stop.fill") { model.cancel() }
            } else {
                Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                    .disabled(model.root == nil)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            PathBar(path: model.path) { depth in model.go(toDepth: depth); selection = [] }
            Divider()
            if case .scanning(_, let detail) = model.phase {
                ScanStatusView(title: "Measuring…", detail: detail, progress: nil) { model.cancel() }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            if model.skippedProtected {
                FullDiskAccessBanner(message: "App containers need Full Disk Access to be measured.")
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            if let current = model.current {
                HStack(spacing: 0) {
                    ScrollView(.vertical) {
                        StorageDonut(node: current) { node in
                            if node.canDrillDown { model.open(node); selection = [] } else { selection = [node.id] }
                        }
                        .padding(16)
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    Divider()
                    table(current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }

    private func table(_ current: StorageNode) -> some View {
        let rows = current.children.sorted(using: sortOrder)
        let colorIndex = Dictionary(uniqueKeysWithValues: StorageDonut.slices(for: current).enumerated().map { ($1.id, $0) })
        return Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { node in
                HStack(spacing: 8) {
                    if node.isAggregate {
                        Image(systemName: "ellipsis.circle").frame(width: 18).foregroundStyle(.secondary)
                    } else {
                        FileIcon(url: node.url)
                    }
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    if node.inaccessibleCount > 0 {
                        Image(systemName: "lock").font(.caption).foregroundStyle(.tertiary)
                            .help("Some items couldn't be read. Actual size may be larger.")
                    }
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("Size", value: \.size) { node in
                HStack(spacing: 8) {
                    SizeBar(fraction: Double(node.size) / Double(max(current.size, 1)),
                            tint: colorIndex[node.id].map { StorageDonut.color(at: $0) } ?? .gray)
                        .frame(width: 60)
                    Text(Format.bytes(node.size)).monospacedDigit()
                }
            }
            .width(min: 130, ideal: 150)
            TableColumn("Items", value: \.itemCount) { node in
                Text(node.itemCount.formatted()).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified") { node in
                Text(node.modified.map { Format.date($0) } ?? "").foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: StorageNode.ID.self) { ids in
            let nodes = rows.filter { ids.contains($0.id) && !$0.isAggregate }
            if !nodes.isEmpty {
                if nodes.count == 1, let node = nodes.first, node.canDrillDown {
                    Button("Open", systemImage: "arrow.down.right.circle") { model.open(node); selection = [] }
                    Divider()
                }
                FileContextMenu(urls: nodes.map(\.url), quickLook: { previewURL = $0 },
                                onRemove: { model.requestRemoval(nodes) })
            }
        } primaryAction: { ids in
            guard let node = rows.first(where: { ids.contains($0.id) }) else { return }
            if node.canDrillDown { model.open(node); selection = [] } else if !node.isAggregate { FileActions.open(node.url) }
        }
        .onKeyPress(.space) {
            guard let id = selection.first, let node = rows.first(where: { $0.id == id }), !node.isAggregate else { return .ignored }
            previewURL = node.url
            return .handled
        }
    }
}

/// Clickable folder hierarchy, similar to Finder's path bar.
private struct PathBar: View {
    let path: [StorageNode]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: 4) {
                            FileIcon(url: node.url, size: 14)
                            Text(node.name)
                            if index == path.count - 1 {
                                Text(Format.bytes(node.size)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 34)
    }
}

/// A donut chart of a folder's largest children.
struct StorageDonut: View {
    let node: StorageNode
    let onActivate: (StorageNode) -> Void
    @State private var selectedAngle: Int64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Slice: Identifiable {
        let id: String
        let name: String
        let size: Int64
        let node: StorageNode?
    }

    static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo]
    static func color(at index: Int) -> Color { index < palette.count ? palette[index] : .gray }

    static func slices(for node: StorageNode) -> [Slice] {
        let sorted = node.children.sorted { $0.size > $1.size }
        var result = sorted.prefix(palette.count).filter { !$0.isAggregate && $0.size > 0 }
            .map { Slice(id: $0.id, name: $0.name, size: $0.size, node: $0) }
        let rest = node.children.filter { child in !result.contains { $0.id == child.id } }.reduce(0) { $0 + $1.size }
        if rest > 0 { result.append(Slice(id: "\u{0}rest", name: "Everything Else", size: rest, node: nil)) }
        return result
    }

    private var slices: [Slice] { Self.slices(for: node) }

    private var hovered: Slice? {
        guard let selectedAngle else { return nil }
        var cumulative: Int64 = 0
        for slice in slices {
            cumulative += slice.size
            if selectedAngle <= cumulative { return slice }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 14) {
            Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                SectorMark(angle: .value("Size", slice.size), innerRadius: .ratio(0.62), angularInset: 1.2)
                    .cornerRadius(3)
                    .foregroundStyle(slice.node == nil ? Color.gray.opacity(0.45) : Self.color(at: index))
                    .opacity(hovered == nil || hovered?.id == slice.id ? 1 : 0.4)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        VStack(spacing: 2) {
                            Text(Format.bytes(hovered?.size ?? node.size))
                                .font(.title2.weight(.semibold)).monospacedDigit()
                            Text(hovered?.name ?? node.name)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.center)
                                .frame(maxWidth: frame.width * 0.5)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .onTapGesture {
                if let node = hovered?.node { onActivate(node) }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: node.id)
            .frame(height: 240)
            .accessibilityLabel("Storage chart for \(node.name)")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.node == nil ? Color.gray.opacity(0.45) : Self.color(at: index)).frame(width: 8, height: 8)
                        Text(slice.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(slice.size)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }
}
