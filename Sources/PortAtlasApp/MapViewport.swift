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
private struct MapPinch {
    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center
}

/// Both maps share interaction; card text remains native and vectors redraw at each zoom.
struct MapViewport<Content: View>: View {
    @EnvironmentObject private var store: AtlasStore
    let kind: AtlasMapKind
    @ViewBuilder let content: () -> Content
    @FocusState private var keyboardFocused: Bool
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch = MapPinch()
    @ViewState private var naturalSize = CGSize.zero
    @ViewState private var tapExclusions = MapTapExclusions()
    private let range: ClosedRange<CGFloat> = 0.35...2.5
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
    private func fit(_ viewport: CGSize, content: CGSize? = nil) {
        let size = content ?? naturalSize
        guard size.width > 0, size.height > 0 else { return }
        var next = state
        next.zoom = min(1, max(range.lowerBound, min((viewport.width - 48) / size.width, (viewport.height - 100) / size.height)))
        next.pan = .zero; next.fitMode = true; next.initialized = true; update(next)
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
    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let relative = CGSize(width: (pinch.anchor.x - 0.5) * viewport.width, height: (pinch.anchor.y - 0.5) * viewport.height)
            let ratio = scale / state.zoom
            let previewPan = CGSize(width: relative.width - (relative.width - state.pan.width) * ratio + drag.width,
                height: relative.height - (relative.height - state.pan.height) * ratio + drag.height)
            ZStack {
                MapContentBackground()
                content().environment(\.mapScale, scale)
                    .background(GeometryReader { proxy in Color.clear.preference(key: ContentSize.self, value: MeasuredMapSize(size: proxy.size, ready: store.snapshot.modelIdentifier != "Unknown Mac")) })
                    .offset(bounded(previewPan, viewport: viewport, at: scale))
            }
            .frame(width: viewport.width, height: viewport.height).clipped().contentShape(Rectangle())
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
                let natural = CGSize(width: size.width / scale, height: size.height / scale)
                if abs(natural.width - naturalSize.width) > 0.5 || abs(natural.height - naturalSize.height) > 0.5 { naturalSize = natural }
                // Attach/detach and telemetry do not reset a user's view.
                if measured.ready && !state.initialized { fit(viewport, content: natural) }
            }
            .onChange(of: store.fitRevision) { _, _ in if store.activeMapKind == kind { fit(viewport) } }
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
                        let origin = proxy[area.bounds].origin
                        return area.path.applying(CGAffineTransform(translationX: origin.x, y: origin.y))
                    }))
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    Button { zoom(state.zoom / 1.2, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 24, height: 24) }.help("Zoom out").accessibilityLabel("Zoom out").disabled(scale <= range.lowerBound)
                    Text("\(Int(scale * 100))%").monospacedDigit().frame(width: 40)
                    Button { zoom(state.zoom * 1.2, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 24, height: 24) }.help("Zoom in").accessibilityLabel("Zoom in").disabled(scale >= range.upperBound)
                    Divider().frame(height: 16)
                    Button("Fit All") { fit(viewport) }.help("Fit all connections · ⌘0")
                    Button("Focus Selection") { store.focusRevision += 1 }.disabled(store.selection == nil).help("Center selection · ⌘2")
                    if kind == .physical {
                        Divider().frame(height: 16)
                        Toggle(isOn: $store.animateConnections) { Image(systemName: "waveform.path").frame(width: 24, height: 24) }.toggleStyle(.button).accessibilityLabel("Animate connections").help("Animate connections. Motion does not represent measured traffic or power.")
                    }
                }.font(.callout).buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 10)
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
                            Label("Data", systemImage: "arrow.left.arrow.right").foregroundStyle(MapPalette.data)
                        }
                        if store.physicalTopology.sockets.contains(where: { store.carriesDisplay($0) }) {
                            Label("Display", systemImage: "display").foregroundStyle(MapPalette.display)
                        }
                        if store.powerRoute != nil {
                            Label("Power in", systemImage: "arrow.down").foregroundStyle(MapPowerStyle.incoming)
                        }
                        if store.physicalTopology.sockets.contains(where: { store.suppliesPower($0) }) {
                            Label("Power out", systemImage: "arrow.up").foregroundStyle(MapPowerStyle.outgoing)
                        }
                    }.font(.caption).padding(16).allowsHitTesting(false)
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
            .accessibilityHint("Drag to move, pinch to zoom. Arrow keys move the map. Fit All shows all connections.")
        }
    }
}
