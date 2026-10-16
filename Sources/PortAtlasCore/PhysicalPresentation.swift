import Foundation

/// Display-only simplification. Never mutates the discovered topology.
public struct PhysicalPresentation {
    public let snapshot: TopologySnapshot
    public let preferences: ComponentPlacementPreferences
    public init(snapshot: TopologySnapshot, preferences: ComponentPlacementPreferences = ComponentPlacementPreferences()) {
        self.snapshot = snapshot; self.preferences = preferences
    }
    public func placement(for node: HardwareNode) -> ComponentPlacement { preferences.placement(for: node, in: snapshot) }
    public func shouldSeparate(_ node: HardwareNode, automatically: Bool) -> Bool {
        switch placement(for: node) { case .automatic: return automatically; case .grouped: return false; case .separate: return true }
    }

    /// Restrict grouping to a router with exactly one direct, leaf NVMe endpoint.
    /// USB hubs, multi-drive enclosures and routers with other functions stay expanded.
    public func combinedStorage(for router: HardwareNode) -> HardwareNode? {
        guard router.kind == .hub, router.transport != nil else { return nil }
        let children = snapshot.children(of: router.id)
        guard children.count == 1, let storage = children.first,
              storage.kind == .device, storage.transport == "PCIe / NVMe storage",
              storage.interfaceClasses?.contains(8) == true,
              snapshot.children(of: storage.id).isEmpty, placement(for: storage) != .separate else { return nil }
        return storage
    }
    public var combinedStorageIDs: Set<String> {
        Set(snapshot.nodes.compactMap { combinedStorage(for: $0)?.id })
    }
}
