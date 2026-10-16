import Foundation

public enum NodeKind: String, Codable, Sendable {
    case controller, port, hub, device
    public var symbol: String {
        switch self {
        case .controller: return "cpu"
        case .port: return "cable.connector"
        case .hub: return "point.3.connected.trianglepath.dotted"
        case .device: return "externaldrive"
        }
    }
}

/// An enumeration speed is a link rate, never measured throughput or a maximum capability.
public struct LinkSpeed: Codable, Equatable, Sendable {
    public let megabitsPerSecond: Double
    public let source: String
    public var label: String {
        megabitsPerSecond >= 1000
            ? "\(megabitsPerSecond / 1000, specifier: "%g") Gb/s"
            : "\(megabitsPerSecond, specifier: "%g") Mb/s"
    }
    public init(megabitsPerSecond: Double, source: String) {
        self.megabitsPerSecond = megabitsPerSecond; self.source = source
    }
    /// IOThunderboltPort current speed code (per lane) and negotiated width.
    /// Unknown/asymmetric encodings must not be presented as a symmetric rate.
    public static func thunderbolt(speedCode: Int, width: Int) -> LinkSpeed? {
        guard [1, 2].contains(width), let lane = [8: 10000.0, 4: 20000.0, 2: 40000.0][speedCode] else { return nil }
        return LinkSpeed(megabitsPerSecond: lane * Double(width), source: "IOThunderboltPort current link speed × width")
    }
    /// Supported speed is a mask of per-lane rates, not a certification generation.
    public static func thunderboltMaximum(speedMask: Int, width: Int) -> LinkSpeed? {
        guard [1, 2].contains(width), speedMask > 0, speedMask & ~14 == 0 else { return nil }
        let lane: Double = speedMask & 2 != 0 ? 40000 : speedMask & 4 != 0 ? 20000 : 10000
        return LinkSpeed(megabitsPerSecond: lane * Double(width), source: "IOThunderboltPort supported link speed × width")
    }
    /// IOUSBHost's enum differs from the legacy USB Device Speed enum.
    public static func hostEnumeration(_ raw: Int) -> LinkSpeed? {
        let values: [Int: Double] = [1: 12, 2: 1.5, 3: 480, 4: 5000, 5: 10000, 6: 20000]
        return values[raw].map { LinkSpeed(megabitsPerSecond: $0, source: "IOUSBHost enumeration speed") }
    }
}

// Foundation's interpolation doesn't include SwiftUI's specifier overload.
private extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: Double, specifier: String) {
        appendLiteral(String(format: specifier, value))
    }
}

public struct PowerFact: Codable, Equatable, Sendable {
    public let label: String
    public let milliamps: Int
    public let source: String
    public init(label: String, milliamps: Int, source: String) {
        self.label = label; self.milliamps = milliamps; self.source = source
    }
}

public struct HardwareNode: Identifiable, Codable, Equatable, Sendable {
    /// Registry entry IDs only identify nodes within the current running system.
    public let id: String
    public let name: String
    public let kind: NodeKind
    public let parentID: String?
    public let registryPath: String
    public let manufacturer: String?
    public let vendorID: Int?
    public let productID: Int?
    public let locationID: UInt32?
    public let speed: LinkSpeed?
    public let power: [PowerFact]
    public let portNumber: Int?
    /// Validated UsbIOPort target, never inferred from a controller or Location ID.
    public let connectorPath: String?
    public let interfaceClasses: [Int]?
    public let displayID: UInt32?
    public let transport: String?
    public let isUSB4Tunnel: Bool?

    public var symbol: String {
        if displayID != nil { return "display" }
        if transport != nil && kind == .hub { return "bolt.fill" }
        guard kind == .device else { return kind.symbol }
        // Product-name hints affect decoration only, never topology or link facts.
        if vendorID == 0x05ac && name.lowercased().contains("iphone") { return "iphone" }
        if interfaceClasses?.contains(8) == true { return "externaldrive" }
        if interfaceClasses?.contains(3) == true { return "keyboard" }
        if interfaceClasses?.contains(1) == true { return "speaker.wave.2" }
        return "shippingbox"
    }

    public var deviceDescription: String {
        if let transport { return transport }
        if kind == .hub { return "USB hub" }
        if interfaceClasses?.contains(8) == true { return "USB storage" }
        return kind == .device ? "USB device" : kind.rawValue.capitalized
    }

    public init(id: String, name: String, kind: NodeKind, parentID: String? = nil,
                registryPath: String = "", manufacturer: String? = nil, vendorID: Int? = nil,
                productID: Int? = nil, locationID: UInt32? = nil, speed: LinkSpeed? = nil,
                power: [PowerFact] = [], portNumber: Int? = nil,
                connectorPath: String? = nil, interfaceClasses: [Int]? = nil, isUSB4Tunnel: Bool? = nil, transport: String? = nil, displayID: UInt32? = nil) {
        self.displayID = displayID
        self.transport = transport
        self.id = id; self.name = name; self.kind = kind; self.parentID = parentID
        self.registryPath = registryPath; self.manufacturer = manufacturer
        self.vendorID = vendorID; self.productID = productID; self.locationID = locationID
        self.speed = speed; self.power = power; self.portNumber = portNumber
        self.connectorPath = connectorPath; self.interfaceClasses = interfaceClasses; self.isUSB4Tunnel = isUSB4Tunnel
    }
}

public struct TopologySnapshot: Sendable {
    public let nodes: [HardwareNode]
    public let capturedAt: Date
    public let modelIdentifier: String
    public let notices: [String]
    public let connectors: [HardwareConnector]
    public let powerStatus: MacPowerStatus
    public let thunderboltDevices: [ThunderboltDevice]
    public let formFactor: MacFormFactor
    public let storage: [StorageVolume]
    public init(nodes: [HardwareNode], modelIdentifier: String, notices: [String] = [], capturedAt: Date = Date(), connectors: [HardwareConnector] = [], storage: [StorageVolume] = [], formFactor: MacFormFactor = .laptop, powerStatus: MacPowerStatus = MacPowerStatus(), thunderboltDevices: [ThunderboltDevice] = []) {
        self.nodes = nodes; self.modelIdentifier = modelIdentifier
        self.notices = notices; self.capturedAt = capturedAt
        self.connectors = connectors; self.storage = storage; self.formFactor = formFactor
        self.powerStatus = powerStatus; self.thunderboltDevices = thunderboltDevices
    }
    public static let empty = TopologySnapshot(nodes: [], modelIdentifier: "Unknown Mac")
    public var powerRoute: PowerRoute? { PowerRouting.resolve(connectors: connectors, externalPower: powerStatus.externalPower) }
    public var connectedAccessoryCount: Int {
        let roots = accessoryRoots
        let matched = Set(roots.compactMap { connectorPath(for: $0.id) })
        return matched.count + roots.filter { connectorPath(for: $0.id) == nil }.count
    }
    public var deviceCount: Int { nodes.filter { $0.kind == .device || $0.kind == .hub }.count }
    public func node(_ id: String?) -> HardwareNode? { nodes.first { $0.id == id } }
    public func children(of id: String) -> [HardwareNode] {
        nodes.filter { $0.parentID == id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var roots: [HardwareNode] {
        nodes.filter { node in node.parentID == nil || !nodes.contains { $0.id == node.parentID } }
            .sorted { $0.registryPath < $1.registryPath }
    }
    /// Bounded traversal also makes malformed fixtures and a disappearing parent safe.
    public func ancestry(of id: String) -> [HardwareNode] {
        var result: [HardwareNode] = [], visited: Set<String> = []
        var current = node(id)
        while let value = current, visited.insert(value.id).inserted {
            result.append(value); current = node(value.parentID)
        }
        return result.reversed()
    }
    public var accessoryRoots: [HardwareNode] {
        nodes.filter { ($0.kind == .device || $0.kind == .hub) && connectionParent(of: $0.id) == nil }
    }
    public func connectionParent(of id: String) -> HardwareNode? {
        ancestry(of: id).dropLast().last { $0.kind == .device || $0.kind == .hub }
    }
    public func connectionChildren(of id: String) -> [HardwareNode] {
        nodes.filter { ($0.kind == .device || $0.kind == .hub) && connectionParent(of: $0.id)?.id == id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func connectorPath(for id: String) -> String? {
        let paths = Set(ancestry(of: id).compactMap(\.connectorPath))
        return paths.count == 1 ? paths.first : nil
    }
    public func rootPort(for id: String) -> HardwareNode? {
        ancestry(of: id).first { $0.kind == .port }
    }
}
