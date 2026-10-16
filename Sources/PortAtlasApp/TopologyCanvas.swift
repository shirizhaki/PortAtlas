import SwiftUI
import PortAtlasCore

private struct TreeLayout {
    var positions: [String: CGPoint] = [:]
    var size = CGSize(width: 300, height: 150)
    init(snapshot: TopologySnapshot, collapsed: Set<String>) {
        let rowSpacing = CGFloat(108 + 60 * (Dictionary(grouping: snapshot.storage, by: \.deviceID).values.map(\.count).max() ?? 0))
        var row: CGFloat = 0, maxDepth = 0
        var visited: Set<String> = []
        func visit(_ node: HardwareNode, depth: Int) -> CGFloat? {
            guard visited.insert(node.id).inserted else { return nil }
            maxDepth = max(maxDepth, depth)
            let children = collapsed.contains(node.id) ? [] : snapshot.children(of: node.id)
            let childRows = children.compactMap { visit($0, depth: depth + 1) }
            let y: CGFloat
            if let first = childRows.first, let last = childRows.last { y = (first + last) / 2 }
            else { y = row * rowSpacing + 60; row += 1 }
            positions[node.id] = CGPoint(x: CGFloat(depth) * 270 + 135, y: y)
            return y
        }
        for root in snapshot.roots { _ = visit(root, depth: 0); row += 0.35 }
        // Cyclic or otherwise malformed graphs still remain inspectable.
        for node in snapshot.nodes where !visited.contains(node.id) &&
            !snapshot.ancestry(of: node.id).dropLast().contains(where: { collapsed.contains($0.id) }) {
            _ = visit(node, depth: 0); row += 0.35
        }
        size = CGSize(width: CGFloat(maxDepth + 1) * 270 + 30, height: max(150, row * rowSpacing + 30))
    }
}

struct TopologyCanvas: View {
    @EnvironmentObject private var store: AtlasStore
    @Environment(\.mapScale) private var scale
    var body: some View { MapViewport(kind: .logical) { LogicalMapContent() } }
}

private struct LogicalMapContent: View {
    @EnvironmentObject private var store: AtlasStore
    @Environment(\.mapScale) private var scale
    var body: some View { graph(TreeLayout(snapshot: store.snapshot, collapsed: store.collapsed)) }
    private func graph(_ layout: TreeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.scaleBy(x: scale, y: scale)
                for node in store.snapshot.nodes {
                    guard let parentID = node.parentID, !store.collapsed.contains(parentID),
                          let start = layout.positions[parentID], let end = layout.positions[node.id] else { continue }
                    var path = Path()
                    let a = CGPoint(x: start.x + 112, y: start.y), b = CGPoint(x: end.x - 112, y: end.y)
                    path.move(to: a)
                    path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                    context.stroke(path, with: .color((node.displayID != nil ? MapPalette.display : MapPalette.data).opacity(store.emphasis(for: node.id) * 0.5)), lineWidth: 2)
                }
            }.frame(width: layout.size.width * scale, height: layout.size.height * scale).allowsHitTesting(false)
            ForEach(store.snapshot.nodes) { node in
                if let parentID = node.parentID, !store.collapsed.contains(parentID), let start = layout.positions[parentID], let end = layout.positions[node.id] {
                    let a = CGPoint(x: (start.x + 112) * scale, y: start.y * scale), b = CGPoint(x: (end.x - 112) * scale, y: end.y * scale)
                    let path = Path { value in
                        value.move(to: a)
                        value.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                    }
                    ConnectionHitArea(path: path, label: "Connection to " + node.name) { store.selection = .connection(node.id) }
                }
            }
            ForEach(store.snapshot.nodes) { node in
                if let position = layout.positions[node.id] {
                    nodeCard(node).position(x: position.x * scale, y: position.y * scale)
                }
            }
        }.frame(width: layout.size.width * scale, height: layout.size.height * scale)
    }
    private func nodeCard(_ node: HardwareNode) -> some View {
        let selected = store.selection == .device(node.id) || store.selection == .connection(node.id)
        let volumes = store.snapshot.storage.filter { $0.deviceID == node.id }
        let socket = store.physicalPort(for: node).flatMap { port in store.physicalTopology.sockets.first { $0.id == port.id } }
        let powered = node.kind == .port && socket.map { store.receivesPower($0) || store.suppliesPower($0) } == true
        let active = node.kind == .device || node.kind == .hub || (node.kind == .port && !store.snapshot.children(of: node.id).isEmpty)
        let height = max(34, CGFloat(76 + 60 * volumes.count) * scale)
        let card = VStack(alignment: .leading, spacing: 8 * scale) {
            nodeHeader(node)
        if scale >= 0.55 { ForEach(volumes) { StorageUsageView(volume: $0) } }
        }
        return card.padding(12 * scale).frame(width: 224 * scale, height: height)
        .modifier(MapCardSurface(selected: selected, scale: scale, appearance: MapConnectionAppearance(active: active, display: node.displayID != nil, power: powered, powerOutgoing: powered && socket.map { store.suppliesPower($0) } == true, data: active && node.displayID == nil), emphasized: store.emphasis(for: node.id) == 1, select: { store.selection = .device(node.id) }))
        .anchorPreference(key: FocusAnchors.self, value: .bounds) { [node.id: $0] }
        .accessibilityElement(children: .contain)
    }
    private func nodeHeader(_ node: HardwareNode) -> some View {
        let hasChildren = !store.snapshot.children(of: node.id).isEmpty
        return HStack(spacing: 10 * scale) {
            Button { store.selectedID = node.id } label: {
                HStack(spacing: 10 * scale) {
                    if scale >= 0.6 {
                    Image(systemName: node.symbol).font(.system(size: 17 * max(0.85, scale))).foregroundStyle(node.displayID != nil ? MapPalette.display : MapPalette.data)
                        .frame(width: 32 * scale, height: 36 * scale).background(MapPalette.data.opacity(0.08), in: RoundedRectangle(cornerRadius: 8 * scale))
                    }
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text(scale < 0.6 && node.kind == .controller ? store.mapTitle(for: node).replacingOccurrences(of: "USB Controller", with: "Host") : store.mapTitle(for: node))
                            .font(.system(size: 12 * max(0.85, scale), weight: .semibold)).lineLimit(1)
                        if scale >= 0.6 || node.kind == .port {
                            Text(scale < 0.6 ? subtitle(node).replacingOccurrences(of: " branch", with: "") : subtitle(node))
                                .font(.system(size: scale < 0.6 ? 9 : 11 * max(0.85, scale))).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(node.kind == .port
                      ? "USB 2 and USB 3 branches can share a physical port."
                      : node.name)
            if hasChildren {
                Button {
                    if store.collapsed.contains(node.id) { store.collapsed.remove(node.id) } else { store.collapsed.insert(node.id) }
                } label: {
                    Image(systemName: store.collapsed.contains(node.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10 * max(0.85, scale), weight: .semibold)).frame(width: max(18, 16 * scale), height: 28 * scale)
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Expand or collapse this branch")
            }
        }
    }
    private func subtitle(_ node: HardwareNode) -> String {
        switch node.kind {
        case .controller: return "USB host controller"
        case .port:
            return node.transport ?? "USB branch"
        case .hub, .device:
            if let displayID = node.displayID { return store.displayLabel(displayID) ?? "Display" }
            let transport = node.transport?.replacingOccurrences(of: " router", with: "") ?? "USB"
            return transport + " · " + (node.speed?.label ?? "Speed unavailable")
        }
    }
}
