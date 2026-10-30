import SwiftUI
import PortAtlasCore

typealias ViewState<Value> = SwiftUI.State<Value>

struct AtlasView: View {
    @EnvironmentObject private var store: AtlasStore
    @ViewState private var showingPortMatcher = false
    /// Unplaced connections the user already dismissed; a new one brings the banner back.
    @ViewState private var dismissedPlacementKeys: Set<String> = []
    private var logical: Bool { store.activeMapKind == .logical }
    private var placementKeys: Set<String> {
        let topology = store.physicalTopology
        return Set(topology.unplaced.map(\.id)).union(topology.sockets.isEmpty ? ["no-sockets"] : [])
    }
    var body: some View {
        VStack(spacing: 0) {
            if let error = store.discoveryError { banner(error + " Showing the last successful snapshot.") }
            if let error = store.monitoringError { banner(error) }
            if !logical, case let keys = placementKeys, !keys.isEmpty, !keys.isSubset(of: dismissedPlacementKeys) {
                HStack {
                    Label("Some connections need a physical position.", systemImage: "cable.connector").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Match ports", systemImage: "slider.horizontal.3") { showingPortMatcher = true }
                    Button { dismissedPlacementKeys.formUnion(keys) } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Dismiss until another connection needs a position").accessibilityLabel("Dismiss")
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
            Divider()
            HStack(spacing: 0) {
                // Only the active map is built; each map's zoom and pan live in the store.
                Group {
                    if logical { TopologyCanvas() } else { PhysicalMapView() }
                }
                if store.inspectorVisible {
                    Divider()
                    DeviceDetailView().environmentObject(store)
                }
            }

        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MapWindowReader { store.registerMapWindow($0) })
        .modifier(MapFullScreenToolbar())
        .sheet(isPresented: $showingPortMatcher) { PortMatchingView().environmentObject(store) }
        // onExitCommand fires only when a focused view receives the key; observing Escape at
        // the window works wherever focus is. It is consumed only while the inspector is open.
        .background(EscapeKeyReader {
            guard store.inspectorVisible else { return false }
            store.hideInspector(); return true
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { store.updateFullScreenState($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { store.updateFullScreenState($0) }
        .onAppear { store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            Task { @MainActor in await Task.yield(); store.updateTelemetryVisibility() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { store.updateFullScreenState($0); store.updateTelemetryVisibility() }
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
                }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let input = store.liveInput {
                    Button { store.selection = .mac } label: {
                        // Toolbar buttons default to icon-only; the reading is the point of this item.
                        Label(input.label, systemImage: "bolt.fill").labelStyle(.titleAndIcon).monospacedDigit().foregroundStyle(MapPowerStyle.incoming)
                    }.help("Current power input to this Mac")
                        .accessibilityLabel("Current power input: " + input.label)
                }
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.isRefreshing).help("Refresh connections · ⌘R")
                Button { store.toggleInspector() } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }.help(store.inspectorVisible ? "Hide inspector · Escape" : "Show inspector")
                Button { store.toggleMapFullScreen() } label: {
                    Label(store.mapIsFullScreen ? "Exit Full Screen" : "Enter Full Screen", systemImage: store.mapIsFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.keyboardShortcut("f", modifiers: [.control, .command])
                    .help((store.mapIsFullScreen ? "Exit full screen" : "Enter full screen") + " · ⌃⌘F")
                    .accessibilityLabel(store.mapIsFullScreen ? "Exit Full Screen" : "Enter Full Screen")
            }
        }
    }
    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 10)
    }
}

/// Keep native window controls and a visible exit action available in full screen.
private struct MapFullScreenToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.windowToolbarFullScreenVisibility(.visible)
        } else { content }
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
