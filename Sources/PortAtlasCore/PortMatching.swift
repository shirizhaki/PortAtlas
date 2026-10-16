import Foundation

/// Session-only observations for the matching guide. No positional guesses or device serials.
public struct PortMatchingObservation: Equatable, Sendable {
    public let roots: [String: Set<String>]
    public init(snapshot: TopologySnapshot) {
        var roots: [String: Set<String>] = [:]
        for connector in snapshot.connectors where connector.kind == .usbC || connector.kind == .usbA {
            roots[connector.id] = Set(snapshot.accessoryRoots.filter {
                snapshot.connectorPath(for: $0.id) == connector.id
            }.map(\.id))
        }
        self.roots = roots
    }
    /// A device arriving at exactly one host connector is a suggestion for user confirmation.
    /// Adding a child to an existing dock does not move that dock's host root.
    public func suggestedConnector(since previous: Self) -> String? {
        let changed = roots.keys.filter { !(roots[$0] ?? []).subtracting(previous.roots[$0] ?? []).isEmpty }
        return changed.count == 1 ? changed.first : nil
    }
    public var onlyOccupiedConnector: String? {
        let occupied = roots.filter { !$0.value.isEmpty }.map(\.key)
        return occupied.count == 1 ? occupied.first : nil
    }
}

extension PortConfiguration {
    /// Reuse the connector's existing position or an explicitly chosen empty slot.
    /// Build the change in a value copy; the app saves it before adopting it.
    @discardableResult
    public mutating func match(_ connector: HardwareConnector, snapshot: TopologySnapshot, side: PortSide, name: String, replacing portID: UUID? = nil) -> UUID? {
        guard (connector.kind == .usbC || connector.kind == .usbA), snapshot.connectors.contains(where: { $0.id == connector.id }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let current = PhysicalTopology(snapshot: snapshot, configuration: self).sockets.first { $0.connectors.contains { $0.id == connector.id } }?.id
        let id = portID ?? current ?? UUID()
        if let index = ports.firstIndex(where: { $0.id == id }) {
            // A slot in use by a different connector must be cleared explicitly in Settings.
            let occupants = PhysicalTopology(snapshot: snapshot, configuration: self).sockets.first { $0.id == id }?.connectors ?? []
            guard occupants.allSatisfy({ $0.id == connector.id }) else { return nil }
            ports[index].side = side; ports[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            guard portID == nil else { return nil }
            ports.append(PhysicalPort(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), side: side))
        }
        // If choosing a different empty slot, avoid retaining a duplicate placeholder for this route.
        if let current, current != id { removePort(current) }
        assignConnector(connector, snapshot: snapshot, to: id)
        return id
    }
}
