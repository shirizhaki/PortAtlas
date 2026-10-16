import SwiftUI
import PortAtlasCore

typealias ViewState<Value> = SwiftUI.State<Value>

struct AtlasView: View {
    @EnvironmentObject private var store: AtlasStore
    @ViewState private var showingPortMatcher = false
    private var logical: Bool { store.activeMapKind == .logical }
    var body: some View {
        VStack(spacing: 0) {
            if let error = store.discoveryError { banner(error + " Showing the last successful snapshot.") }
            if let error = store.monitoringError { banner(error) }
            if !logical && (store.physicalTopology.sockets.isEmpty || !store.physicalTopology.unplaced.isEmpty) {
                HStack {
                    Label("Some connections need a physical position.", systemImage: "cable.connector").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Match ports", systemImage: "slider.horizontal.3") { showingPortMatcher = true }
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
            Divider()
            HStack(spacing: 0) {
                ZStack {
                    PhysicalMapView().opacity(logical ? 0 : 1).allowsHitTesting(!logical).disabled(logical).accessibilityHidden(logical)
                    TopologyCanvas().opacity(logical ? 1 : 0).allowsHitTesting(logical).disabled(!logical).accessibilityHidden(!logical)
                }
                if store.selection != nil {
                    Divider()
                    DeviceDetailView().environmentObject(store)
                }
            }

        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MapWindowReader { store.registerMapWindow($0) })
        .modifier(MapFullScreenToolbar())
        .sheet(isPresented: $showingPortMatcher) { PortMatchingView().environmentObject(store) }
        .onExitCommand { store.selection = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { store.updateFullScreenState($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { store.updateFullScreenState($0) }
        .onAppear { store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            Task { @MainActor in await Task.yield(); store.updateTelemetryVisibility() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { store.updateFullScreenState($0); store.updateTelemetryVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didUpdateNotification)) { _ in store.updateTelemetryVisibility() }
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
                        Label(input.label, systemImage: "bolt.fill").monospacedDigit().foregroundStyle(.green)
                    }.help("Current power input to this Mac")
                        .accessibilityLabel("Current power input: " + input.label)
                }
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.isRefreshing).help("Refresh connections · ⌘R")
                Button { store.selection = store.selection == nil ? .mac : nil } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }.help(store.selection == nil ? "Show inspector" : "Hide inspector · Escape")
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
