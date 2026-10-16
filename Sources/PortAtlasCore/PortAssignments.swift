import Foundation

public enum PortSide: String, CaseIterable, Codable, Identifiable, Sendable {
    case left, right, front, back
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // The old custom-side bucket becomes Front during migration.
        if raw == "other" { self = .front; return }
        guard let side = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized port side")
        }
        self = side
    }
}

public struct PhysicalPort: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var side: PortSide
    /// nil uses automatic evidence; .unknown explicitly keeps capability unknown.
    public var capability: PortCapability?
    public init(id: UUID = UUID(), name: String, side: PortSide, capability: PortCapability? = nil) {
        self.id = id; self.name = name; self.side = side; self.capability = capability
    }
}

public struct PortAssignment: Codable, Equatable, Sendable {
    public let modelIdentifier: String
    public let registryPath: String
    public let physicalPortID: UUID
    public let assignedAt: Date
    public let connectorPath: String?
    public init(modelIdentifier: String, registryPath: String, physicalPortID: UUID, assignedAt: Date = Date(), connectorPath: String? = nil) {
        self.modelIdentifier = modelIdentifier; self.registryPath = registryPath
        self.physicalPortID = physicalPortID; self.assignedAt = assignedAt
        self.connectorPath = connectorPath
    }
}

public struct PortConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var ports: [PhysicalPort] = []
    public var assignments: [PortAssignment] = []
    public init() {}
    public func physicalPort(for node: HardwareNode, model: String) -> PhysicalPort? {
        guard node.kind == .port, !node.registryPath.isEmpty,
              let id = uniqueAssignmentID(for: node, model: model) else { return nil }
        return ports.first { $0.id == id }
    }
    private func uniqueAssignmentID(for node: HardwareNode, model: String) -> UUID? {
        let candidates = Set(assignments.filter {
            $0.modelIdentifier == model &&
            ($0.registryPath == node.registryPath || (node.connectorPath != nil && $0.connectorPath == node.connectorPath))
        }.map(\.physicalPortID))
        return candidates.count == 1 ? candidates.first : nil
    }
    public mutating func assign(_ node: HardwareNode, model: String, to portID: UUID?) {
        guard node.kind == .port, !node.registryPath.isEmpty else { return }
        assignments.removeAll { $0.modelIdentifier == model && $0.registryPath == node.registryPath }
        if let portID, ports.contains(where: { $0.id == portID }) {
            assignments.append(PortAssignment(modelIdentifier: model, registryPath: node.registryPath, physicalPortID: portID, connectorPath: node.connectorPath))
        }
    }
    public mutating func assignConnector(_ connector: HardwareConnector, snapshot: TopologySnapshot, to portID: UUID?) {
        guard snapshot.connectors.contains(where: { $0.id == connector.id }) else { return }
        let roots = snapshot.nodes.filter { $0.kind == .port && $0.connectorPath == connector.id }
        let paths = Set(roots.map(\.registryPath))
        assignments.removeAll {
            $0.modelIdentifier == snapshot.modelIdentifier &&
            ($0.connectorPath == connector.id || paths.contains($0.registryPath) || (portID != nil && $0.physicalPortID == portID))
        }
        guard let portID, ports.contains(where: { $0.id == portID }) else { return }
        assignments.append(PortAssignment(modelIdentifier: snapshot.modelIdentifier, registryPath: roots.first?.registryPath ?? connector.id,
                                          physicalPortID: portID, connectorPath: connector.id))
    }
    public func ports(on side: PortSide) -> [PhysicalPort] { ports.filter { $0.side == side } }
    /// Swapping only same-side entries preserves other sides and all connector assignments.
    public mutating func movePort(_ id: UUID, by offset: Int) {
        guard let current = ports.firstIndex(where: { $0.id == id }) else { return }
        let indices = ports.indices.filter { ports[$0].side == ports[current].side }
        guard let position = indices.firstIndex(of: current), indices.indices.contains(position + offset) else { return }
        ports.swapAt(current, indices[position + offset])
    }
    public mutating func removePort(_ id: UUID) {
        ports.removeAll { $0.id == id }; assignments.removeAll { $0.physicalPortID == id }
    }
}

public enum ConfigurationError: Error { case unsupportedVersion, invalidData }

/// Stored in Application Support, never in the source checkout or a hardware capture.
public struct ConfigurationStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: ConfigurationStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigurationStore(url: directory.appendingPathComponent("PortAtlas/ports.json"))
    }
    public func load() throws -> PortConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return PortConfiguration() }
        var configuration = try JSONDecoder().decode(PortConfiguration.self, from: Data(contentsOf: url))
        guard (1...3).contains(configuration.schemaVersion) else { throw ConfigurationError.unsupportedVersion }
        guard Set(configuration.ports.map(\.id)).count == configuration.ports.count else { throw ConfigurationError.invalidData }
        if configuration.schemaVersion < 3 {
            // Old position fields are read only during migration and never written again.
            struct Legacy: Decodable {
                struct Port: Decodable { let id: UUID; let position: String? }
                let ports: [Port]
            }
            let legacy = try JSONDecoder().decode(Legacy.self, from: Data(contentsOf: url))
            let ranks = Dictionary(uniqueKeysWithValues: legacy.ports.map { ($0.id, ["far": 0, "middle": 1, "near": 2][$0.position ?? ""] ?? 1) })
            for side in PortSide.allCases {
                let indices = configuration.ports.indices.filter { configuration.ports[$0].side == side }
                let ordered = indices.enumerated().sorted {
                    let a = ranks[configuration.ports[$0.element].id] ?? 1
                    let b = ranks[configuration.ports[$1.element].id] ?? 1
                    return a == b ? $0.offset < $1.offset : a < b
                }.map { configuration.ports[$0.element] }
                for (index, port) in zip(indices, ordered) { configuration.ports[index] = port }
            }
            for index in configuration.ports.indices {
                let side = configuration.ports[index].side
                if ["Left · far", "Left · near", "Right · far", "Right · near"].contains(configuration.ports[index].name) {
                    let number = configuration.ports(on: side).firstIndex(where: { $0.id == configuration.ports[index].id })! + 1
                    configuration.ports[index].name = "\(side.label) \(number)"
                }
            }
        }
        configuration.schemaVersion = 3
        return configuration
    }
    public func save(_ configuration: PortConfiguration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
