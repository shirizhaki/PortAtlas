import Foundation

/// Session-only presentation hints, never proof of an accessory's enclosure boundary.
public struct AttachmentHistory: Sendable {
    public private(set) var laterAttachments: Set<String> = []
    private var firstSeen: [String: Date] = [:]
    private var previousIDs: Set<String> = []
    public init() {}
    public mutating func observe(_ snapshot: TopologySnapshot) {
        let ids = Set(snapshot.nodes.map(\.id))
        laterAttachments.formIntersection(ids)
        firstSeen = firstSeen.filter { ids.contains($0.key) }
        for node in snapshot.nodes {
            if !previousIDs.contains(node.id), node.kind == .device || node.kind == .hub,
               let parent = snapshot.node(node.parentID), parent.kind == .hub,
               previousIDs.contains(parent.id), let since = firstSeen[parent.id],
               snapshot.capturedAt.timeIntervalSince(since) >= 2 {
                laterAttachments.insert(node.id)
            }
            if firstSeen[node.id] == nil { firstSeen[node.id] = snapshot.capturedAt }
        }
        previousIDs = ids
    }
}
