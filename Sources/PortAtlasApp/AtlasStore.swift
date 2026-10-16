import SwiftUI
import CoreGraphics
import PortAtlasCore
import PortAtlasHardware

enum AtlasSelection: Equatable {
    case mac, socket(UUID), connector(String), device(String), connection(String), display(UInt32)
}

@MainActor
final class AtlasStore: ObservableObject {
    @Published private(set) var liveSnapshot = TopologySnapshot.empty
    @Published private(set) var displays: [DisplayDevice] = []
    @Published var configuration = PortConfiguration()
    @Published var selection: AtlasSelection?
    var selectedID: String? {
        get { if case .device(let id) = selection { return id }; return nil }
        set { selection = newValue.map(AtlasSelection.device) }
    }
    @Published var physicalViewport = MapViewportState()
    @Published var logicalViewport = MapViewportState()
    @Published var focusRevision = 0
    @Published var fitRevision = 0
    @Published var animateConnections = true
    @Published var activeMapKind = AtlasMapKind.physical
    @Published private(set) var mapIsFullScreen = false
    @Published private(set) var powerSample = PowerSample()
    @Published private(set) var networkLinks: [NetworkLink] = []
    @Published private(set) var powerHistory = PowerHistory()
    private var telemetryTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private let mapWindows = NSHashTable<NSWindow>.weakObjects()
    private var telemetryGeneration = 0
    private var telemetryVisible = false
    var focusKey: String? {
        switch selection {
        case .mac: return "mac"
        case .socket(let id): return id.uuidString
        case .connector(let id), .device(let id), .connection(let id): return id
        case .display(let id): return snapshot.nodes.first { $0.displayID == id }?.id ?? "display-\(id)"
        case nil: return nil
        }
    }
    func focusKey(in kind: AtlasMapKind) -> String? {
        if kind == .logical {
            switch selection {
            case .mac: return snapshot.roots.first?.id
            case .socket(let id):
                let paths = physicalTopology.sockets.first { $0.id == id }?.connectors.map(\.id) ?? []
                return snapshot.nodes.first { paths.contains($0.connectorPath ?? "") }?.id
            case .connector(let id): return snapshot.nodes.first { $0.connectorPath == id }?.id
            default: break
            }
        } else if case .device(let id) = selection,
                  presentation.combinedStorageIDs.contains(id) {
            return snapshot.connectionParent(of: id)?.id
        }
        return focusKey
    }
    func focusKeys(in kind: AtlasMapKind) -> [String] {
        var keys = focusKey(in: kind).map { [$0] } ?? []
        let node: HardwareNode?
        switch selection {
        case .device(let id), .connection(let id): node = snapshot.node(id)
        case .display(let id): node = snapshot.nodes.first { $0.displayID == id }
        default: node = nil
        }
        if let node {
            keys += snapshot.ancestry(of: node.id).reversed().map(\.id)
            if let connector = snapshot.connectorPath(for: node.id) { keys.append(connector) }
            if node.kind == .controller { keys.append("mac") }
        }
        return keys
    }
    var routeNodeIDs: Set<String> {
        switch selection {
        case .device(let id), .connection(let id): return Set(snapshot.ancestry(of: id).map(\.id))
        case .socket(let id):
            let connectors = physicalTopology.sockets.first { $0.id == id }?.connectors.map(\.id) ?? []
            return Set(snapshot.nodes.filter { connectors.contains(snapshot.connectorPath(for: $0.id) ?? "") }.map(\.id))
        case .connector(let id): return Set(snapshot.nodes.filter { snapshot.connectorPath(for: $0.id) == id }.map(\.id))
        case .display(let id): return Set(snapshot.nodes.filter { $0.displayID == id }.flatMap { snapshot.ancestry(of: $0.id).map(\.id) })
        default: return []
        }
    }
    func emphasis(for id: String) -> Double { routeNodeIDs.isEmpty || routeNodeIDs.contains(id) ? 1 : 0.35 }
    func emphasis(for socket: SocketConnection) -> Double {
        if case .socket(let id) = selection { return id == socket.id ? 1 : 0.35 }
        if case .connector(let id) = selection { return socket.connectors.contains { $0.id == id } ? 1 : 0.35 }
        return routeNodeIDs.isEmpty || snapshot.nodes.contains { node in routeNodeIDs.contains(node.id) && socket.connectors.contains { $0.id == snapshot.connectorPath(for: node.id) } } ? 1 : 0.35
    }
    var liveInput: PowerMeasurement? { powerSample.liveInput(at: Date()) }
    var powerStatus: MacPowerStatus { Date().timeIntervalSince(powerSample.sampledAt) <= 5 ? powerSample.status : snapshot.powerStatus }
    var powerRoute: PowerRoute? { PowerRouting.resolve(connectors: snapshot.connectors, externalPower: powerStatus.externalPower) }
    func displayLabel(_ id: UInt32) -> String? {
        guard let display = displays.first(where: { $0.id == id }) else { return nil }
        return display.mapLabel
    }
    func updateTelemetryVisibility() {
        setTelemetryVisible(!NSApp.isHidden && mapWindows.allObjects.contains { $0.isVisible && !$0.isMiniaturized })
    }
    func registerMapWindow(_ window: NSWindow) {
        mapWindows.add(window)
        if window.isMainWindow || mapWindows.allObjects.count == 1 {
            mapIsFullScreen = window.styleMask.contains(.fullScreen)
        }
        updateTelemetryVisibility()
    }
    func updateFullScreenState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, mapWindows.contains(window) else { return }
        mapIsFullScreen = window.styleMask.contains(.fullScreen)
    }
    func toggleMapFullScreen() {
        guard let window = NSApp.keyWindow, mapWindows.contains(window) else { return }
        window.toggleFullScreen(nil)
    }
    func setTelemetryVisible(_ visible: Bool) {
        guard telemetryVisible != visible else { return }
        telemetryVisible = visible
        telemetryGeneration += 1; telemetryTask?.cancel(); telemetryTask = nil
        networkTask?.cancel(); networkTask = nil
        powerSample = PowerSample(); powerHistory.reset(); networkLinks = []
        guard visible else { return }
        let generation = telemetryGeneration
        let sampler = PowerSampler()
        telemetryTask = Task { [weak self] in
            defer { sampler.close() }
            while !Task.isCancelled {
                let connectors = self?.snapshot.connectors ?? []
                let sample = await Task.detached(priority: .utility) { sampler.sample(connectors: connectors) }.value
                guard let self, self.telemetryGeneration == generation, !Task.isCancelled else { return }
                self.powerSample = sample; self.powerHistory.append(sample)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // A large network-device registry walk must not delay the power sampler.
        networkTask = Task { [weak self] in
            while !Task.isCancelled {
                let deviceIDs = Set(self?.snapshot.nodes.map(\.id) ?? [])
                let links = await Task.detached(priority: .utility) { NetworkTelemetry.sample(deviceIDs: deviceIDs) }.value
                guard let self, self.telemetryGeneration == generation, !Task.isCancelled else { return }
                self.networkLinks = links
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    @Published private(set) var componentPreferences = ComponentPlacementPreferences()
    @Published private(set) var componentLayoutError: String?
    private var componentLayoutNeedsReset = false
    private let componentStore = ComponentPlacementStore.standard
    @Published var expandedComponents: Set<String> = []
    var presentation: PhysicalPresentation { PhysicalPresentation(snapshot: snapshot, preferences: componentPreferences) }
    @Published var collapsed: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var discoveryError: String?
    @Published private(set) var monitoringError: String?
    @Published private(set) var settingsError: String?
    @Published private(set) var settingsNeedReset = false
    private var displayObserver: NSObjectProtocol?
    private var displaySettlingTask: Task<Void, Never>?
    private var volumeObservers: [NSObjectProtocol] = []
    private(set) var attachmentHistory = AttachmentHistory()
    private var monitor: USBMonitor?
    private var refreshAgain = false
    private let settingsStore = ConfigurationStore.standard
    var snapshot: TopologySnapshot { liveSnapshot }
    var activeConnectionCount: Int {
        let topology = physicalTopology
        return topology.sockets.filter { !$0.devices.isEmpty || $0.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty } }.count +
            topology.unplaced.filter { !$0.devices.isEmpty || $0.connector?.connectionActive == true || $0.connector?.links.isEmpty == false }.count
    }
    var physicalTopology: PhysicalTopology {
        PhysicalTopology(snapshot: snapshot, configuration: configuration)
    }

    init() {
        do { configuration = try settingsStore.load() }
        catch { settingsError = "Saved port settings could not be read. Reset them to enable saving."; settingsNeedReset = true }
        do { componentPreferences = try componentStore.load() }
        catch { componentLayoutError = "Saved component layout could not be read."; componentLayoutNeedsReset = true }
        monitor = USBMonitor { [weak self] in self?.refresh() }
        do { try monitor?.start() }
        catch { monitoringError = "Automatic updates unavailable: \(error.localizedDescription)" }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification, NSWorkspace.didWakeNotification] {
            volumeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh(); self?.updateTelemetryVisibility() }
            })
        }
        volumeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setTelemetryVisible(false) }
        })
        updateDisplays()
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateDisplays(); self.refresh()
                self.displaySettlingTask?.cancel()
                self.displaySettlingTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
                    self?.updateDisplays(); self?.refresh()
                }
            }
        }
        refresh()
    }
    private func updateDisplays() {
        let signals = DisplayDiscovery.signals()
        let capacities = DisplayDiscovery.linkCapacities()
        let edids = DisplayDiscovery.edids()
        displays = NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  CGDisplayIsBuiltin(id) == 0 else { return nil }
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayDevice(id: id, name: screen.localizedName, width: mode?.width ?? CGDisplayPixelsWide(id), height: mode?.height ?? CGDisplayPixelsHigh(id), refreshRate: mode?.refreshRate,
                signal: signals[id]?.signal, nativeResolution: signals[id]?.nativeResolution,
                renderedResolution: mode.flatMap { DisplayResolution(width: $0.pixelWidth, height: $0.pixelHeight) }, linkCapacity: capacities[id], edid: edids[id], availableModes: DisplayDiscovery.availableModes(for: id))
        }
    }
    deinit {
        telemetryTask?.cancel(); networkTask?.cancel(); displaySettlingTask?.cancel()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        for observer in volumeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func refresh() {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        Task {
            let result = await Task.detached(priority: .utility) { Result { try USBDiscovery.snapshot() } }.value
            switch result {
            case .success(let snapshot):
                expandedComponents.formIntersection(Set(snapshot.nodes.map(\.id)))
                attachmentHistory.observe(snapshot)
                let previousRoute = powerRoute?.connectorID
                liveSnapshot = snapshot; discoveryError = nil
                updateDisplays()
                if previousRoute != powerRoute?.connectorID || powerSample.status.externalPower != snapshot.powerStatus.externalPower {
                    powerHistory.reset()
                    powerSample = PowerSample(status: snapshot.powerStatus)
                }
                networkLinks.removeAll { snapshot.node($0.deviceID) == nil }
                validateSelection()
            case .failure(let error): discoveryError = error.localizedDescription
            }
            isRefreshing = false
            if refreshAgain { refreshAgain = false; refresh() }
        }
    }
    private func validateSelection() {
        switch selection {
        case .device(let id), .connection(let id): if snapshot.node(id) == nil { selection = nil }
        case .connector(let id): if !snapshot.connectors.contains(where: { $0.id == id }) { selection = nil }
        case .socket(let id): if !physicalTopology.sockets.contains(where: { $0.id == id }) { selection = nil }
        case .display(let id): if !displays.contains(where: { $0.id == id }) { selection = nil }
        default: break
        }
    }
    func saveSettings() {
        guard !settingsNeedReset else { return }
        do { try settingsStore.save(configuration); settingsError = nil }
        catch { settingsError = "Port settings could not be saved: \(error.localizedDescription)" }
    }
    func resetSettings() {
        configuration = PortConfiguration(); settingsNeedReset = false; saveSettings()
    }
    var unassignedDisplays: [DisplayDevice] {
        displays.filter { display in !snapshot.nodes.contains { $0.displayID == display.id } }
    }
    func connectionLabel(for socket: SocketConnection) -> String {
        if socket.isMagSafe { return socket.connectors.contains { $0.connectionActive == true } ? "MagSafe connected" : "MagSafe" }
        if socket.isHDMI { return "HDMI" }
        let dataRoots = socket.devices.filter { $0.displayID == nil }
        if let router = dataRoots.first(where: { $0.transport != nil && $0.kind == .hub }) {
            return (router.transport?.replacingOccurrences(of: " router", with: "") ?? "Thunderbolt / USB4") + " · " + (router.speed?.label ?? "Speed unavailable")
        }
        if !dataRoots.isEmpty {
            let fastest = dataRoots.compactMap(\.speed).max { $0.megabitsPerSecond < $1.megabitsPerSecond }
            return "USB · " + (fastest?.label ?? "Speed unavailable")
        }
        if socket.connectors.flatMap(\.links).contains(where: { $0.kind == .thunderboltUSB4 }) { return "Thunderbolt / USB4 · Speed unavailable" }
        if socket.devices.contains(where: { $0.displayID != nil }) || socket.connectors.flatMap(\.links).contains(where: { $0.isDisplay }) { return "DisplayPort" }
        if socket.connectors.contains(where: { $0.powerContractWatts != nil }) { return "USB-C · Power connected" }
        if socket.connectors.contains(where: { $0.connectionActive == true }) { return "Connected · Protocol unknown" }
        return capabilityLabel(for: socket.port)
    }
    func mapTitle(for node: HardwareNode) -> String {
        if node.kind == .port { return physicalPort(for: node)?.name ?? node.name }
        if node.kind == .controller, let index = snapshot.nodes.filter({ $0.kind == .controller }).firstIndex(where: { $0.id == node.id }) {
            return "USB Controller \(index + 1)"
        }
        return node.name
    }
    var liveOutputs: [PortPowerOutput] {
        snapshot.connectors.compactMap { output(for: $0.id) }
    }
    var totalOutput: Double? {
        PortPowerOutput.measuredTotal(liveOutputs, at: Date())
    }
    func canPlaceComponent(_ node: HardwareNode) -> Bool {
        (node.kind == .device || node.kind == .hub) && node.displayID == nil &&
        snapshot.connectionParent(of: node.id)?.kind == .hub && componentPreferences.key(for: node, in: snapshot) != nil
    }
    func setPlacement(_ placement: ComponentPlacement, for node: HardwareNode) {
        guard canPlaceComponent(node), !componentLayoutNeedsReset else { return }
        var next = componentPreferences; next.set(placement, for: node, in: snapshot)
        do { try componentStore.save(next); componentPreferences = next; componentLayoutError = nil }
        catch { componentLayoutError = "Component layout could not be saved." }
    }
    func resetComponentLayout() {
        do {
            let next = ComponentPlacementPreferences(); try componentStore.save(next)
            componentPreferences = next; componentLayoutError = nil; componentLayoutNeedsReset = false
        } catch { componentLayoutError = "Component layout could not be saved." }
    }
    func deviceAppearance(_ node: HardwareNode) -> MapConnectionAppearance {
        if let socket = physicalTopology.sockets.first(where: { $0.devices.contains { $0.id == node.id } }) {
            return socketAppearance(socket)
        }
        return MapConnectionAppearance(active: true, display: node.displayID != nil, data: node.displayID == nil)
    }
    func socketAppearance(_ socket: SocketConnection) -> MapConnectionAppearance {
        MapConnectionAppearance(active: !socket.devices.isEmpty || socket.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty },
            display: carriesDisplay(socket), power: receivesPower(socket) || suppliesPower(socket),
            powerOutgoing: !receivesPower(socket) && suppliesPower(socket),
            data: socket.devices.contains { $0.displayID == nil } || socket.connectors.flatMap(\.links).contains { $0.kind == .usb3 || $0.kind == .thunderboltUSB4 })
    }
    func output(for connectorID: String) -> PortPowerOutput? {
        guard connectorID != powerRoute?.connectorID,
              snapshot.connectors.contains(where: { $0.id == connectorID && $0.connectionActive == true }) else { return nil }
        return powerSample.outputs.first { $0.connectorID == connectorID && $0.isFresh(at: Date()) }
    }
    func output(for socket: SocketConnection) -> PortPowerOutput? {
        let readings = socket.connectors.compactMap { output(for: $0.id) }
        return readings.count == 1 ? readings.first : nil
    }
    func suppliesPower(_ socket: SocketConnection) -> Bool { output(for: socket) != nil }
    func receivesPower(_ socket: SocketConnection) -> Bool {
        socket.connectors.contains { $0.id == powerRoute?.connectorID }
    }
    func carriesDisplay(_ socket: SocketConnection) -> Bool {
        socket.connectors.flatMap(\.links).contains { $0.isDisplay } ||
        snapshot.nodes.contains { node in node.displayID != nil && socket.connectors.contains { $0.id == snapshot.connectorPath(for: node.id) } }
    }
    func capabilityLabel(for port: PhysicalPort) -> String {
        if physicalTopology.sockets.first(where: { $0.id == port.id })?.isHDMI == true { return "HDMI" }
        if let manual = port.capability { return manual.label }
        let connectors = physicalTopology.sockets.first { $0.id == port.id }?.connectors ?? []
        let speeds = connectors.compactMap(\.maximumLinkSpeed)
        if Set(speeds.map(\.megabitsPerSecond)).count == 1, let speed = speeds.first {
            return "Thunderbolt / USB4 · up to " + speed.label
        }
        let reported = Set(connectors.flatMap(\.reportedTransports))
        return HardwareConnector(id: "", reportedTransports: reported.sorted()).reportedSupportLabel ?? PortCapability.unknown.label
    }
    func capabilitySource(for port: PhysicalPort) -> String {
        if physicalTopology.sockets.first(where: { $0.id == port.id })?.isHDMI == true { return "Hardware-reported HDMI connector" }
        if port.capability != nil { return "Port settings" }
        if let socket = physicalTopology.sockets.first(where: { $0.id == port.id }),
           let speed = socket.connectors.compactMap(\.maximumLinkSpeed).first { return speed.source }
        return "Hardware-reported protocols; exact generation may be unavailable"
    }
    func physicalPort(for node: HardwareNode) -> PhysicalPort? {
        guard let path = snapshot.connectorPath(for: node.id) else { return nil }
        return physicalTopology.sockets.first { $0.connectors.contains { $0.id == path } }?.port
    }
    func assign(_ node: HardwareNode, to id: UUID?) {
        configuration.assign(node, model: snapshot.modelIdentifier, to: id); saveSettings()
    }
    func saveMatchedPort(connectorID: String, side: PortSide, name: String, replacing portID: UUID?) -> Bool {
        guard !settingsNeedReset, let connector = liveSnapshot.connectors.first(where: { $0.id == connectorID }) else { return false }
        var next = configuration
        guard next.match(connector, snapshot: liveSnapshot, side: side, name: name, replacing: portID) != nil else { return false }
        do {
            try settingsStore.save(next)
            configuration = next; settingsError = nil
            return true
        } catch {
            settingsError = "Port settings could not be saved: \(error.localizedDescription)"
            return false
        }
    }
    func matchConnector(_ connectorID: String?, to portID: UUID) {
        guard !settingsNeedReset else { return }
        configuration.assignments.removeAll { $0.physicalPortID == portID && $0.modelIdentifier == liveSnapshot.modelIdentifier }
        if let connector = liveSnapshot.connectors.first(where: { $0.id == connectorID }) {
            configuration.assignConnector(connector, snapshot: liveSnapshot, to: portID)
        }
        saveSettings()
    }
}
