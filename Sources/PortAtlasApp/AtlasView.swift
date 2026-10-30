import SwiftUI
import PortAtlasCore

typealias ViewState<Value> = SwiftUI.State<Value>

struct AtlasView: View {
    @EnvironmentObject private var store: AtlasStore
    @ViewState private var showingPortMatcher = false
    private var logical: Bool { store.activeMapKind == .logical }
    var body: some View {
        // The standard three-column Mac layout: source list, map, inspector.
        NavigationSplitView {
            SidebarView(showingPortMatcher: $showingPortMatcher)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.discoveryError { banner(error + " Showing the last successful snapshot.") }
                if let error = store.monitoringError { banner(error) }
                // Only the active map is built; each map's zoom and pan live in the store.
                // The map runs under the toolbar, whose controls float over it, as in Maps.
                // The toolbar's height is read here, before the map ignores it.
                GeometryReader { proxy in
                    Group {
                        if logical { TopologyCanvas() } else { PhysicalMapView() }
                    }
                    .environment(\.mapTopInset, proxy.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .top)
                }
            }
            .background(MapPalette.canvas)
            // No toolbar background over the map, so no band or hairline crosses it.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationSplitViewColumnWidth(min: 560, ideal: 900)
        }
        // The system inspector column: resizable, toolbar-aware, and glass on macOS 26.
        .inspector(isPresented: Binding(get: { store.inspectorVisible }, set: { if !$0 { store.hideInspector() } })) {
            DeviceDetailView().environmentObject(store)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .navigationTitle("PortAtlas")
        .navigationSubtitle(connectionSubtitle)
        .background(MapWindowReader { store.registerMapWindow($0) })
        // Keep the toolbar, and its window controls, visible in full screen.
        .windowToolbarFullScreenVisibility(.visible)
        .sheet(isPresented: $showingPortMatcher) { PortMatchingView().environmentObject(store) }
        // onExitCommand fires only when a focused view receives the key; observing Escape at
        // the window works wherever focus is. It is consumed only while the inspector is open.
        .background(EscapeKeyReader {
            guard store.inspectorVisible else { return false }
            store.hideInspector(); return true
        })
        .onAppear { store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            Task { @MainActor in await Task.yield(); store.updateTelemetryVisibility() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in store.updateTelemetryVisibility() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Map view", selection: Binding(get: { logical }, set: { store.activeMapKind = $0 ? .logical : .physical })) {
                    Text("Physical").tag(false)
                    Text("Logical").tag(true)
                // Natural size: the toolbar fits its glass to the control, so a fixed frame left it off-center.
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let input = store.liveInput {
                    Button { store.selection = .mac } label: {
                        // Toolbar buttons default to icon-only; the reading is the point of this item.
                        Label { Text(input.label).foregroundStyle(MapPowerStyle.incoming) } icon: { Image(systemName: "bolt.fill").foregroundStyle(MapPalette.Graphic.incoming) }
                            .labelStyle(.titleAndIcon).monospacedDigit()
                    }.help("Current power input to this Mac")
                        .accessibilityLabel("Current power input: " + input.label)
                }
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.isRefreshing).help("Refresh connections · ⌘R")
                Button { store.toggleInspector() } label: {
                    Label(store.inspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
                }.help(store.inspectorVisible ? "Hide inspector · Escape" : "Show inspector")
            }
        }
    }
    private var connectionSubtitle: String {
        let count = store.activeConnectionCount
        return count == 1 ? "1 connection" : "\(count) connections"
    }
    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 10)
    }
}

/// Register the actual map window instead of inferring it from size or title.
private struct MapWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowView { WindowView(onWindow: onWindow) }
    func updateNSView(_ view: WindowView, context: Context) { view.onWindow = onWindow }
    final class WindowView: NSView {
        var onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                if let window { self?.onWindow(window) }
            }
        }
    }
}

/// Escape for this window only; sheets and other windows keep their own handling.
private struct EscapeKeyReader: NSViewRepresentable {
    var handle: () -> Bool
    func makeNSView(context: Context) -> MonitorView { MonitorView(handle: handle) }
    func updateNSView(_ view: MonitorView, context: Context) { view.handle = handle }
    final class MonitorView: NSView {
        var handle: () -> Bool
        private var monitor: Any?
        init(handle: @escaping () -> Bool) { self.handle = handle; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, event.window === self.window,
                      // Caps Lock (also an input-source switch on many layouts) is not a modifier here.
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      self.window?.attachedSheet == nil else { return event }
                return self.handle() ? nil : event
            }
        }
    }
}
