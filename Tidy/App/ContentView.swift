import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowSize: CGSize = .zero

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            Sidebar(selection: sidebarSelection)
                .navigationSplitViewColumnWidth(min: 232, ideal: 240, max: 300)
        } detail: {
            detail
                .scrollContentBackground(.hidden)
                .id(app.selection)
                .transition(.opacity)
                .animation(MotionAware.animation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: app.selection)
        }
        .background {
            GeometryReader { proxy in
                backdrop.onAppear { windowSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in windowSize = size }
            }
        }
        .environment(\.windowSize, windowSize)
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: $app.pendingRemoval) { request in
            RemovalReviewSheet(request: request)
        }
        .onAppear {
            app.settings.applyAppearance()
            #if DEBUG
            DebugSnapshots.runIfRequested(app: app)
            #endif
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if #available(macOS 26.0, *) {
            AmbientBackdrop()
        } else {
            AmbientBackdrop()
        }
    }

    /// The Settings row opens the native Settings window rather than changing the selection.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { app.selection }, set: { newValue in
            if newValue == .settings {
                openSettings()
            } else {
                app.selection = newValue
            }
        })
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection ?? .dashboard {
        case .dashboard: DashboardView()
        case .smartCleanup: SmartCleanupView()
        case .storageExplorer: StorageExplorerView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .downloads: DownloadsView()
        case .appManager: AppManagerView()
        case .leftovers: LeftoversView()
        case .loginItems: LoginItemsView()
        case .performance: PerformanceView()
        case .maintenance: MaintenanceView()
        case .history: ActivityHistoryView()
        case .settings: DashboardView()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: SidebarItem?
    @FocusState private var isFocused: Bool
    @Namespace private var glassSpace

    private var navigable: [SidebarItem] { SidebarItem.Section.allCases.flatMap(\.items).filter { $0 != .settings } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SidebarItem.Section.allCases) { section in
                    VStack(alignment: .leading, spacing: 1) {
                        if section != .overview {
                            Text(section.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.items) { item in
                            SidebarRow(item: item, badge: badge(for: item), isSelected: selection == item, glassSpace: glassSpace) {
                                selection = item
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .glassGroup(spacing: 20)
        }
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .background { PanelBackdrop() }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StorageFooter()
        }
    }

    /// A short size for a badge, such as "8.8 GB" or "640 MB".
    private func compactBytes(_ bytes: Int64) -> String {
        let style = ByteCountFormatter()
        style.countStyle = .file
        style.zeroPadsFractionDigits = false
        let full = style.string(fromByteCount: bytes)
        guard let space = full.firstIndex(of: " "), let value = Double(full[..<space].replacingOccurrences(of: ",", with: ".")) else { return full }
        // Whole numbers from 10 up keep the badge narrow enough for the row title.
        let number = value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
        return number + full[space...]
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let current = navigable.firstIndex(of: selection ?? .dashboard) ?? 0
        let next = min(max(current + step, 0), navigable.count - 1)
        selection = navigable[next]
        return .handled
    }

    private func badge(for item: SidebarItem) -> String? {
        switch item {
        case .smartCleanup:
            if app.cleanup.phase.hasResults, app.cleanup.reclaimable > 0 { return compactBytes(app.cleanup.reclaimable) }
        case .duplicates:
            if app.duplicates.phase.hasResults, !app.duplicates.groups.isEmpty { return "\(app.duplicates.groups.count)" }
        case .leftovers:
            if app.leftovers.phase.hasResults, !app.leftovers.groups.isEmpty { return "\(app.leftovers.groups.count)" }
        default:
            break
        }
        return nil
    }
}

/// One navigation row: a monochrome glyph and label, with a soft accent pill when selected.
private struct SidebarRow: View {
    let item: SidebarItem
    let badge: String?
    let isSelected: Bool
    let glassSpace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(.quaternary.opacity(isSelected ? 0.35 : 0.7)))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.5))
                }
            }
            .selectionGlass(isSelected, id: item.rawValue, in: glassSpace)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isSelected)
        .accessibilityLabel(badge.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension EnvironmentValues {
    @Entry var windowSize: CGSize = .zero
}

extension View {
    /// Puts a side panel, such as an inspector, on the window's color field.
    func panelBackdrop() -> some View {
        scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { PanelBackdrop() }
    }
}

/// The window's color field, lined up with the one behind the detail pane so side
/// panels read as one continuous surface, dimmed for legible text.
struct PanelBackdrop: View {
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            AmbientBackdrop()
                .frame(width: max(windowSize.width, proxy.size.width), height: max(windowSize.height, proxy.size.height))
                .offset(x: -origin.x, y: -origin.y)
                .overlay((scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.22 : 0.35))
        }
        .ignoresSafeArea()
        .clipped()
        .allowsHitTesting(false)
    }
}

private extension View {
    /// The selected row carries the glass itself, so its label renders on top of
    /// the glass, and the pill morphs from row to row.
    @ViewBuilder
    func selectionGlass(_ isSelected: Bool, id: String, in namespace: Namespace.ID) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(isSelected ? Glass.regular.tint(Color.accentColor.opacity(0.28)).interactive() : Glass.identity, in: shape)
                .glassEffectID(isSelected ? "selection" : id, in: namespace)
        } else {
            self.background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.clear), in: shape)
        }
    }
}

/// A System Settings style icon: white glyph on a colored rounded-square tile.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// Live startup-disk space, pinned to the bottom of the sidebar.
private struct StorageFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let volume = app.volume {
            let tint: Color = volume.utilization > 0.9 ? .red : volume.utilization > 0.8 ? .orange : .accentColor
            Button {
                app.selection = .storageExplorer
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(volume.name).font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(Format.percent(volume.utilization))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(tint.gradient)
                                .frame(width: max(4, proxy.size.width * volume.utilization))
                        }
                    }
                    .frame(height: 5)
                    Text("\(Format.bytes(volume.available)) of \(Format.bytes(volume.total)) available")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
                .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(volume.name), \(Format.bytes(volume.available)) available")
            .help("Open Storage Explorer")
        }
    }
}
