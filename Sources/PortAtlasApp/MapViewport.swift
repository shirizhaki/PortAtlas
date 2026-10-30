import SwiftUI
import PortAtlasCore

struct FocusAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct WireInteractionArea {
    let path: Path
    let bounds: Anchor<CGRect>
}
struct WireInteractionAreas: PreferenceKey {
    static var defaultValue: [WireInteractionArea] = []
    static func reduce(value: inout [WireInteractionArea], nextValue: () -> [WireInteractionArea]) { value += nextValue() }
}
private struct MapTapExclusions: Equatable {
    var cards: [CGRect] = []
    var wires: [Path] = []
    func contains(_ point: CGPoint) -> Bool { cards.contains { $0.contains(point) } || wires.contains { $0.contains(point) } }
}
private struct MapTapExclusionPreference: PreferenceKey {
    static var defaultValue = MapTapExclusions()
    static func reduce(value: inout MapTapExclusions, nextValue: () -> MapTapExclusions) {
        let next = nextValue(); value.cards += next.cards; value.wires += next.wires
    }
}
private struct MeasuredMapSize: Equatable {
    var size = CGSize.zero
    var ready = false
}
private struct ContentSize: PreferenceKey {
    static var defaultValue = MeasuredMapSize()
    static func reduce(value: inout MeasuredMapSize, nextValue: () -> MeasuredMapSize) {
        let next = nextValue()
        // Controls and overlays contribute an empty default. Keep the actual map.
        if next.size.width > 0 && next.size.height > 0 { value = next }
    }
}
struct MapViewportState {
    var zoom: CGFloat = 1
    var pan = CGSize.zero
    var fitMode = true
    var initialized = false
}
enum AtlasMapKind { case physical, logical }
struct MapZoomRequest: Equatable {
    var revision = 0
    var step = 0
}
private struct MapPinch {
    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center
}

/// Both maps share interaction. The map is laid out once and zoomed as a transform, so nothing
/// reflows while zooming; the viewport renders through drawingGroup, which draws text and
/// vectors at the final on-screen size, so they stay sharp at every zoom.
struct MapViewport<Content: View>: View {
    @EnvironmentObject private var store: AtlasStore
    let kind: AtlasMapKind
    @ViewBuilder let content: () -> Content
    @FocusState private var keyboardFocused: Bool
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch = MapPinch()
    @ViewState private var naturalSize = CGSize.zero
    @ViewState private var tapExclusions = MapTapExclusions()
    /// A map rebuilt in fit mode refits once measured; the window may have resized while it was hidden.
    @ViewState private var refitOnMeasure = true
    private let range: ClosedRange<CGFloat> = 0.2...2.5
    private var state: MapViewportState { kind == .physical ? store.physicalViewport : store.logicalViewport }
    private var scale: CGFloat { min(range.upperBound, max(range.lowerBound, state.zoom * pinch.magnification)) }
    private func update(_ value: MapViewportState) {
        if kind == .physical { store.physicalViewport = value } else { store.logicalViewport = value }
    }
    private func bounded(_ value: CGSize, viewport: CGSize, at zoom: CGFloat) -> CGSize {
        let x = max(0, (naturalSize.width * zoom - viewport.width) / 2) + viewport.width * 0.35
        let y = max(0, (naturalSize.height * zoom - viewport.height) / 2) + viewport.height * 0.35
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    /// Height of the toolbar the map runs under; fitting and corner labels stay below it.
    @Environment(\.mapTopInset) private var topInset
    private func fit(_ viewport: CGSize, content: CGSize? = nil) {
        let size = content ?? naturalSize
        guard size.width > 0, size.height > 0 else { return }
        var next = state
        next.zoom = min(1, max(range.lowerBound, min((viewport.width - 48) / size.width, (viewport.height - topInset - 100) / size.height)))
        next.pan = CGSize(width: 0, height: topInset / 2); next.fitMode = true; next.initialized = true; update(next)
    }
    private func zoom(_ value: CGFloat, around point: CGPoint, viewport: CGSize) {
        var next = state
        let newZoom = min(range.upperBound, max(range.lowerBound, value))
        let ratio = newZoom / next.zoom
        let relative = CGSize(width: point.x - viewport.width / 2, height: point.y - viewport.height / 2)
        next.pan = bounded(CGSize(width: relative.width - (relative.width - next.pan.width) * ratio,
            height: relative.height - (relative.height - next.pan.height) * ratio), viewport: viewport, at: newZoom)
        next.zoom = newZoom; next.fitMode = false; update(next)
    }
    private func move(_ delta: CGSize, viewport: CGSize) {
        var next = state; next.fitMode = false
        next.pan = bounded(CGSize(width: next.pan.width + delta.width, height: next.pan.height + delta.height), viewport: viewport, at: next.zoom)
        update(next)
    }
    private func scroll(_ event: NSEvent, at point: CGPoint, viewport: CGSize) {
        if event.modifierFlags.contains(.command) {
            // Command-scroll zooms around the pointer, like most canvas apps.
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            zoom(state.zoom * exp(delta / 200), around: point, viewport: viewport)
        } else {
            let lines: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            move(CGSize(width: event.scrollingDeltaX * lines, height: event.scrollingDeltaY * lines), viewport: viewport)
        }
    }
    private func logicalPowerSummary(_ route: PowerRoute) -> String {
        let port = store.physicalTopology.sockets.first { $0.connectors.contains { $0.id == route.connectorID } }?.port.name
            ?? store.snapshot.connectors.first { $0.id == route.connectorID }?.label ?? "Unknown port"
        return ["Power in", port, store.liveInput?.label].compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let relative = CGSize(width: (pinch.anchor.x - 0.5) * viewport.width, height: (pinch.anchor.y - 0.5) * viewport.height)
            let ratio = scale / state.zoom
            let previewPan = CGSize(width: relative.width - (relative.width - state.pan.width) * ratio + drag.width,
                height: relative.height - (relative.height - state.pan.height) * ratio + drag.height)
            ZStack {
                content().environment(\.mapScale, 1)
                    .background(GeometryReader { proxy in Color.clear.preference(key: ContentSize.self, value: MeasuredMapSize(size: proxy.size, ready: store.snapshot.modelIdentifier != "Unknown Mac")) })
                    .scaleEffect(scale)
                    .offset(bounded(previewPan, viewport: viewport, at: scale))
            }
            .frame(width: viewport.width, height: viewport.height)
            // Text and shapes are rasterized at the zoomed size instead of magnifying a 100% render.
            .drawingGroup()
            // The grid stays outside the drawing group, so animated wires do not redraw it each frame.
            .background { MapContentBackground(scale: scale, offset: bounded(previewPan, viewport: viewport, at: scale)) }
            .clipped().contentShape(Rectangle())
            .background(ScrollWheelReader { event, point in scroll(event, at: point, viewport: viewport) })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if !tapExclusions.contains(value.location) { store.selection = nil }
            })
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .updating($drag) { value, drag, _ in drag = value.translation }
                .onEnded { move($0.translation, viewport: viewport) })
            .simultaneousGesture(MagnifyGesture()
                .updating($pinch) { value, pinch, _ in pinch = MapPinch(magnification: value.magnification, anchor: value.startAnchor) }
                .onEnded { value in
                    zoom(state.zoom * value.magnification,
                        around: CGPoint(x: value.startAnchor.x * viewport.width, y: value.startAnchor.y * viewport.height), viewport: viewport)
                })
            .onPreferenceChange(ContentSize.self) { measured in
                let size = measured.size
                guard size.width > 0, size.height > 0 else { return }
                let natural = size
                if abs(natural.width - naturalSize.width) > 0.5 || abs(natural.height - naturalSize.height) > 0.5 { naturalSize = natural }
                // Attach/detach and telemetry do not reset a user's view.
                if measured.ready && (!state.initialized || (refitOnMeasure && state.fitMode)) { fit(viewport, content: natural) }
                if measured.ready { refitOnMeasure = false }
            }
            .onChange(of: store.fitRevision) { _, _ in if store.activeMapKind == kind { fit(viewport) } }
            .onChange(of: store.zoomRequest) { _, request in
                guard store.activeMapKind == kind else { return }
                zoom(state.zoom * pow(1.2, CGFloat(request.step)), around: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport)
            }
            .onChange(of: viewport) { _, size in if state.fitMode { fit(size) } }
            .overlayPreferenceValue(FocusAnchors.self) { anchors in
                GeometryReader { proxy in
                    Color.clear.allowsHitTesting(false)
                        .preference(key: MapTapExclusionPreference.self, value: MapTapExclusions(cards: anchors.keys.sorted().compactMap { anchors[$0].map { proxy[$0] } }))
                        .onChange(of: store.focusRevision) { _, _ in
                        guard store.activeMapKind == kind, let anchor = store.focusKeys(in: kind).compactMap({ anchors[$0] }).first else { return }
                        let rect = proxy[anchor]
                        var next = state; next.fitMode = false
                        let target = min(1.2, max(next.zoom, 0.8)), ratio = target / next.zoom
                        next.pan = bounded(CGSize(width: (next.pan.width + viewport.width / 2 - rect.midX) * ratio,
                            height: (next.pan.height + viewport.height / 2 - rect.midY) * ratio), viewport: viewport, at: target)
                        next.zoom = target; update(next)
                    }
                }
            }
            .overlayPreferenceValue(WireInteractionAreas.self) { areas in
                GeometryReader { proxy in
                    Color.clear.allowsHitTesting(false).preference(key: MapTapExclusionPreference.self, value: MapTapExclusions(wires: areas.map { area in
                        // Paths are in layout coordinates; the anchor origin already includes the zoom.
                        let origin = proxy[area.bounds].origin
                        return area.path.applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: origin.x, y: origin.y)))
                    }))
                }
            }
            .overlay(alignment: .bottomLeading) {
                let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
                HStack(spacing: 4) {
                    Button { zoom(state.zoom / 1.2, around: center, viewport: viewport) } label: { MapControlIcon("minus") }
                        .help("Zoom out · ⌘−").accessibilityLabel("Zoom out").disabled(scale <= range.lowerBound)
                    Menu {
                        ForEach([0.5, 0.75, 1, 1.5, 2] as [CGFloat], id: \.self) { level in
                            Button("\(Int(level * 100))%") { zoom(level, around: center, viewport: viewport) }
                        }
                        Divider()
                        Button("Fit All") { fit(viewport) }
                    } label: {
                        Text("\(Int((scale * 100).rounded()))%").monospacedDigit()
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(minWidth: 44)
                        .help("Zoom level").accessibilityLabel("Zoom level \(Int((scale * 100).rounded())) percent")
                    Button { zoom(state.zoom * 1.2, around: center, viewport: viewport) } label: { MapControlIcon("plus") }
                        .help("Zoom in · ⌘=").accessibilityLabel("Zoom in").disabled(scale >= range.upperBound)
                    Divider().frame(height: 18).padding(.horizontal, 4)
                    Button { fit(viewport) } label: { MapControlIcon("arrow.up.left.and.arrow.down.right") }
                        .help("Fit all connections · ⌘0").accessibilityLabel("Fit All")
                    Button { store.focusRevision += 1 } label: { MapControlIcon("scope") }
                        .disabled(store.selection == nil).help("Center selection · ⌘L").accessibilityLabel("Focus Selection")
                    if kind == .physical {
                        Toggle(isOn: $store.animateConnections) { MapControlIcon("waveform.path") }
                            .toggleStyle(.button).accessibilityLabel("Animate connections")
                            .help("Animate connections. Motion does not represent measured traffic or power.")
                    }
                }.buttonStyle(.borderless).padding(.horizontal, 8).padding(.vertical, 5)
                    .modifier(MapControlSurface())
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: MapTapExclusionPreference.self, value: MapTapExclusions(cards: [proxy.frame(in: .named(kind == .physical ? "physical-viewport" : "logical-viewport"))]))
                    }).padding(16)
            }
            .coordinateSpace(name: kind == .physical ? "physical-viewport" : "logical-viewport")
            .onPreferenceChange(MapTapExclusionPreference.self) { tapExclusions = $0 }
            .overlay(alignment: .topTrailing) {
                if kind == .physical {
                    HStack(spacing: 14) {
                        if store.snapshot.nodes.contains(where: { ($0.kind == .device || $0.kind == .hub) && $0.displayID == nil }) {
                            MapLegendItem(title: "Data", symbol: "arrow.left.arrow.right", color: MapPalette.Graphic.data)
                        }
                        if store.physicalTopology.sockets.contains(where: { store.carriesDisplay($0) }) {
                            MapLegendItem(title: "Display", symbol: "display", color: MapPalette.Graphic.display)
                        }
                        if store.powerRoute != nil {
                            MapLegendItem(title: "Power in", symbol: "arrow.down", color: MapPalette.Graphic.incoming)
                        }
                        if store.physicalTopology.sockets.contains(where: { store.suppliesPower($0) }) {
                            MapLegendItem(title: "Power out", symbol: "arrow.up", color: MapPalette.Graphic.outgoing)
                        }
                    }.font(.caption).padding(16).padding(.top, topInset).allowsHitTesting(false)
                } else if let route = store.powerRoute {
                    // The Logical tree has no node for a power-only connection (MagSafe, a bare
                    // charger), so the source is summarized here and links to that connector.
                    Button { store.selection = .connector(route.connectorID) } label: {
                        Label { Text(logicalPowerSummary(route)).foregroundStyle(MapPowerStyle.incoming) }
                            icon: { Image(systemName: "bolt.fill").foregroundStyle(MapPalette.Graphic.incoming) }
                            .monospacedDigit()
                            .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain).font(.callout.weight(.medium))
                    .modifier(MapControlSurface())
                    .help("Show the port this Mac is receiving power through")
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: MapTapExclusionPreference.self, value: MapTapExclusions(cards: [proxy.frame(in: .named("logical-viewport"))]))
                    })
                    .padding(16).padding(.top, topInset)
                }
            }
            .focusable(store.activeMapKind == kind).focusEffectDisabled().focused($keyboardFocused)
            .onAppear { keyboardFocused = store.activeMapKind == kind }
            .onChange(of: store.activeMapKind) { _, active in keyboardFocused = active == kind }
            .onKeyPress(.leftArrow) { move(CGSize(width: 45, height: 0), viewport: viewport); return .handled }
            .onKeyPress(.rightArrow) { move(CGSize(width: -45, height: 0), viewport: viewport); return .handled }
            .onKeyPress(.upArrow) { move(CGSize(width: 0, height: 45), viewport: viewport); return .handled }
            .onKeyPress(.downArrow) { move(CGSize(width: 0, height: -45), viewport: viewport); return .handled }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(kind == .physical ? "Physical connection map" : "Logical connection map")
            .accessibilityHint("Drag or scroll to move, pinch or Command-scroll to zoom. Arrow keys move the map. Fit All shows all connections.")
        }
    }
}

/// SwiftUI has no scroll-wheel event for plain views. A local monitor
/// observes scrolls over this view's bounds and leaves clicks to SwiftUI.
private struct ScrollWheelReader: NSViewRepresentable {
    var onScroll: (NSEvent, CGPoint) -> Void
    func makeNSView(context: Context) -> MonitorView { MonitorView(onScroll: onScroll) }
    func updateNSView(_ view: MonitorView, context: Context) { view.onScroll = onScroll }
    final class MonitorView: NSView {
        var onScroll: (NSEvent, CGPoint) -> Void
        private var monitor: Any?
        init(onScroll: @escaping (NSEvent, CGPoint) -> Void) { self.onScroll = onScroll; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onScroll(event, point)
                return nil
            }
        }
    }
}

/// Floating-control glyphs share one size, so the bar reads as a single native control group.
private struct MapControlIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image(systemName: name).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 26).contentShape(Rectangle())
    }
}

/// A legend entry: the role's vivid symbol beside plain secondary text.
private struct MapLegendItem: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        Label { Text(title).foregroundStyle(.secondary) } icon: { Image(systemName: symbol).foregroundStyle(color) }
    }
}

private struct MapTopInset: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    /// The toolbar height above a full-bleed map.
    var mapTopInset: CGFloat {
        get { self[MapTopInset.self] }
        set { self[MapTopInset.self] = newValue }
    }
}
