import Foundation

/// A validated physical IOPort, also associated with USB roots through UsbIOPort when available.
public struct HardwareConnector: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ConnectorKind
    public let power: ConnectorPower?
    public let cable: CableIdentity?
    public let number: Int?
    public let connectionActive: Bool?
    public let reportedTransports: [String]
    public let maximumLinkSpeed: LinkSpeed?
    /// Transient hardware join identity; never persisted in port settings.
    public let controllerUUID: String?
    public let links: [PortTransportLink]
    /// Selected USB-PD contract, not a measurement of instantaneous consumption.
    public let powerContractWatts: Int?
    public let laneDetails: [String]
    /// A positive report is evidence of support; absence never proves unsupported.
    public var reportedSupportLabel: String? {
        if kind == .hdmi { return "HDMI" }
        let known = [("USB2", "USB 2"), ("USB3", "USB 3"), ("DisplayPort", "DisplayPort")]
            .compactMap { reportedTransports.contains($0.0) ? $0.1 : nil }
        return known.isEmpty ? nil : known.joined(separator: " · ")
    }
    public init(id: String, number: Int? = nil, connectionActive: Bool? = nil, reportedTransports: [String] = [], links: [PortTransportLink] = [], powerContractWatts: Int? = nil, laneDetails: [String] = [], kind: ConnectorKind = .usbC, power: ConnectorPower? = nil, cable: CableIdentity? = nil, maximumLinkSpeed: LinkSpeed? = nil, controllerUUID: String? = nil) {
        self.id = id; self.kind = kind; self.power = power; self.cable = cable; self.number = number; self.connectionActive = connectionActive
        self.reportedTransports = reportedTransports; self.links = links
        self.maximumLinkSpeed = maximumLinkSpeed; self.controllerUUID = controllerUUID
        self.powerContractWatts = power?.contractWatts ?? powerContractWatts; self.laneDetails = laneDetails
    }
    public var label: String { if kind == .magSafe { return "MagSafe" }; if kind == .hdmi { return "HDMI" }; let type = kind == .usbA ? "USB-A" : "USB-C"; return number.map { "\(type) socket \($0)" } ?? "\(type) socket" }
}

public struct SocketConnection: Identifiable, Sendable {
    public let port: PhysicalPort
    public let connectors: [HardwareConnector]
    public let devices: [HardwareNode]
    public let hasSavedAssignment: Bool
    public var id: UUID { port.id }
    public var isUSBA: Bool { connectors.contains { $0.kind == .usbA } }
    public var isHDMI: Bool { connectors.contains { $0.kind == .hdmi } }
    public var isMagSafe: Bool { connectors.contains { $0.kind == .magSafe } }
    public var status: String {
        if isMagSafe { return connectors.contains { $0.connectionActive == true } ? "Cable connected" : "Not connected" }
        if isHDMI { return !devices.isEmpty || connectors.contains { $0.connectionActive == true || !$0.links.isEmpty } ? "Display connected" : "Not connected" }
        if !devices.isEmpty || connectors.contains(where: { !$0.links.isEmpty }) { return "Connected" }
        if connectors.isEmpty { return hasSavedAssignment ? "Connection unavailable" : "Position not matched" }
        return connectors.allSatisfy { $0.connectionActive == false } ? "Empty" : "Connected · USB device not reported"
    }
}

public struct UnplacedConnection: Identifiable, Sendable {
    public let id: String
    public let connector: HardwareConnector?
    public let devices: [HardwareNode]
}

/// A presentation projection. Controllers/companion branches are hidden; real hubs remain.
public struct PhysicalTopology: Sendable {
    public let sockets: [SocketConnection]
    public let unplaced: [UnplacedConnection]
    public init(snapshot: TopologySnapshot, configuration: PortConfiguration) {
        let deviceRoots = snapshot.accessoryRoots
        var connectorOwners: [String: UUID] = [:]
        for connector in snapshot.connectors {
            let roots = snapshot.nodes.filter { $0.kind == .port && $0.connectorPath == connector.id }
            // Legacy assignments that disagree must not silently choose a side.
            let paths = Set(roots.map(\.registryPath))
            let owners = Set(configuration.assignments.filter {
                $0.modelIdentifier == snapshot.modelIdentifier &&
                ($0.connectorPath == connector.id || paths.contains($0.registryPath))
            }.map(\.physicalPortID)).intersection(Set(configuration.ports.map(\.id)))
            if owners.count == 1 { connectorOwners[connector.id] = owners.first }
        }
        var groupedDevices: [String: [HardwareNode]] = [:]
        var unlocated: [HardwareNode] = []
        for device in deviceRoots {
            if let path = snapshot.connectorPath(for: device.id),
               snapshot.connectors.contains(where: { $0.id == path }) {
                groupedDevices[path, default: []].append(device)
            } else { unlocated.append(device) }
        }
        let magSafe = snapshot.formFactor == .laptop ? snapshot.connectors.filter { $0.kind == .magSafe } : []
        let automaticMagSafe = magSafe.count == 1 ? magSafe.first : nil
        let magSafePort = PhysicalPort(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "MagSafe", side: .left)
        if let automaticMagSafe { connectorOwners[automaticMagSafe.id] = magSafePort.id }
        let configured = configuration.ports.map { port in
            let connectors = snapshot.connectors.filter { connectorOwners[$0.id] == port.id }
            return SocketConnection(port: port, connectors: connectors,
                                    devices: connectors.flatMap { groupedDevices[$0.id] ?? [] },
                                    hasSavedAssignment: configuration.assignments.contains {
                                        $0.physicalPortID == port.id && $0.modelIdentifier == snapshot.modelIdentifier
                                    })
        }
        let automatic: [SocketConnection] = automaticMagSafe.map { [SocketConnection(port: magSafePort, connectors: [$0], devices: [], hasSavedAssignment: false)] } ?? []
        // Presence comes from hardware. Position is a default that settings can override.
        let hdmi = snapshot.connectors.filter { $0.kind == .hdmi && connectorOwners[$0.id] == nil }
        let automaticHDMI: [SocketConnection]
        if hdmi.count == 1, let connector = hdmi.first {
            let port = PhysicalPort(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "HDMI", side: snapshot.formFactor == .laptop ? .right : .back)
            connectorOwners[connector.id] = port.id
            automaticHDMI = [SocketConnection(port: port, connectors: [connector], devices: groupedDevices[connector.id] ?? [], hasSavedAssignment: false)]
        } else { automaticHDMI = [] }
        sockets = automatic + automaticHDMI + configured
        unplaced = snapshot.connectors.filter { connectorOwners[$0.id] == nil }.map {
            UnplacedConnection(id: $0.id, connector: $0, devices: groupedDevices[$0.id] ?? [])
        } + unlocated.map { UnplacedConnection(id: $0.id, connector: nil, devices: [$0]) }
    }
}
