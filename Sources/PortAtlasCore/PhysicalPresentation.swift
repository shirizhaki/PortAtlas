import Foundation

/// Display-only simplification. Never mutates the discovered topology.
public struct PhysicalPresentation {
    public let snapshot: TopologySnapshot
    public let preferences: ComponentPlacementPreferences
    /// Placement keys are hashed, so they are resolved once per snapshot, not per frame.
    private let placements: [String: ComponentPlacement]
    public let combinedStorageIDs: Set<String>
    public init(snapshot: TopologySnapshot, preferences: ComponentPlacementPreferences = ComponentPlacementPreferences()) {
        self.snapshot = snapshot; self.preferences = preferences
        var placements: [String: ComponentPlacement] = [:]
        if !preferences.choices.isEmpty {
            for node in snapshot.nodes where placements[node.id] == nil {
                placements[node.id] = preferences.placement(for: node, in: snapshot)
            }
        }
        self.placements = placements
        combinedStorageIDs = Set(snapshot.nodes.compactMap {
            Self.combinedStorage(for: $0, in: snapshot, placements: placements)?.id
        })
    }
    public func placement(for node: HardwareNode) -> ComponentPlacement { placements[node.id] ?? .automatic }
    public func shouldSeparate(_ node: HardwareNode, automatically: Bool) -> Bool {
        switch placement(for: node) { case .automatic: return automatically; case .grouped: return false; case .separate: return true }
    }

    /// Restrict grouping to a router with exactly one direct, leaf NVMe endpoint.
    /// USB hubs, multi-drive enclosures and routers with other functions stay expanded.
    public func combinedStorage(for router: HardwareNode) -> HardwareNode? {
        Self.combinedStorage(for: router, in: snapshot, placements: placements)
    }
    private static func combinedStorage(for router: HardwareNode, in snapshot: TopologySnapshot,
                                        placements: [String: ComponentPlacement]) -> HardwareNode? {
        guard router.kind == .hub, router.transport != nil else { return nil }
        let children = snapshot.children(of: router.id)
        guard children.count == 1, let storage = children.first,
              storage.kind == .device, storage.transport == "PCIe / NVMe storage",
              storage.interfaceClasses?.contains(8) == true,
              snapshot.children(of: storage.id).isEmpty, placements[storage.id] != .separate else { return nil }
        return storage
    }
}
