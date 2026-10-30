import SwiftUI
import PortAtlasCore

/// The source list: this Mac, its physical ports, and what is connected to them.
/// Choosing a row selects the same item on the map and in the inspector.
struct SidebarView: View {
    @EnvironmentObject private var store: AtlasStore
    @Binding var showingPortMatcher: Bool

    var body: some View {
        List(selection: selection) {
            // Like Finder's Recents, the top item needs no section header.
            SidebarRow(title: "This Mac", subtitle: store.snapshot.productName ?? store.snapshot.modelIdentifier,
                       symbol: store.macProduct.symbol)
                .tag(AtlasSelection.mac)
            Section("Ports") {
                ForEach(sockets) { socket in
                    SidebarRow(title: socket.port.name, subtitle: status(of: socket), symbol: symbol(for: socket),
                               active: isActive(socket))
                        .tag(AtlasSelection.socket(socket.id))
                }
                if sockets.isEmpty {
                    Text("No ports matched yet").foregroundStyle(.secondary)
                }
            }
            if !store.physicalTopology.unplaced.isEmpty {
                Section {
                    ForEach(store.physicalTopology.unplaced) { connection in
                        SidebarRow(title: connection.devices.first.map(store.mapTitle) ?? connection.connector?.label ?? "Connection",
                                   subtitle: connection.connector?.label ?? "Port unknown", symbol: "questionmark.circle", active: true)
                            .tag(connection.connector.map { AtlasSelection.connector($0.id) }
                                 ?? connection.devices.first.map { AtlasSelection.device($0.id) } ?? AtlasSelection.mac)
                    }
                    Button("Match Ports…") { showingPortMatcher = true }
                        .buttonStyle(.link)
                } header: {
                    Text("Needs a Position")
                }
            }
            if !devices.isEmpty {
                Section("Devices") {
                    OutlineGroup(devices, children: \.children) { item in
                        SidebarRow(title: store.mapTitle(for: item.node), subtitle: subtitle(for: item.node), symbol: item.node.symbol)
                            .tag(AtlasSelection.device(item.node.id))
                    }
                }
            }
            if !store.displays.isEmpty {
                Section("Displays") {
                    ForEach(store.displays) { display in
                        SidebarRow(title: display.name, subtitle: store.displayLabel(display.id) ?? "Display", symbol: "display")
                            .tag(AtlasSelection.display(display.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
    }

    /// Choosing a row also centers the map on it.
    private var selection: Binding<AtlasSelection?> {
        Binding(get: { store.selection }, set: { value in
            store.selection = value
            if value != nil { store.focusRevision += 1 }
        })
    }
    /// Sockets in physical reading order: left, right, front, back.
    private var sockets: [SocketConnection] {
        let order: [PortSide] = [.left, .right, .front, .back]
        return order.flatMap { side in store.physicalTopology.sockets.filter { $0.port.side == side } }
    }
    private var devices: [SidebarDevice] {
        // One pass groups every device under its connection parent, instead of a scan per node.
        let snapshot = store.snapshot
        var children: [String: [HardwareNode]] = [:]
        var roots: [HardwareNode] = []
        for node in snapshot.nodes where (node.kind == .device || node.kind == .hub) && node.displayID == nil {
            if let parent = snapshot.connectionParent(of: node.id) { children[parent.id, default: []].append(node) }
            else { roots.append(node) }
        }
        return roots.sorted(by: SidebarDevice.byName).map { SidebarDevice(node: $0, children: children) }
    }
    private func isActive(_ socket: SocketConnection) -> Bool {
        !socket.devices.isEmpty || socket.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty }
    }
    private func status(of socket: SocketConnection) -> String {
        isActive(socket) ? store.connectionLabel(for: socket) : socket.status
    }
    private func symbol(for socket: SocketConnection) -> String {
        if socket.isMagSafe { return "powerplug" }
        if socket.isHDMI { return "tv" }
        if socket.isUSBA { return "cable.connector.horizontal" }
        return "cable.connector"
    }
    private func subtitle(for node: HardwareNode) -> String {
        let kind = node.transport?.replacingOccurrences(of: " router", with: "") ?? node.deviceDescription
        return node.speed.map { kind + " · " + $0.label } ?? kind
    }
}

/// One single-line source-list row, as in Finder. The icon tint shows whether something is
/// connected; the status line appears as a tooltip and in the inspector.
private struct SidebarRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var active = true
    var body: some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(active ? Color.accentColor : Color.secondary)
        }
        .help(subtitle)
        .accessibilityValue(subtitle)
    }
}

/// A device and the devices connected through it, for the outline.
private struct SidebarDevice: Identifiable {
    let node: HardwareNode
    let children: [SidebarDevice]?
    var id: String { node.id }
    init(node: HardwareNode, children map: [String: [HardwareNode]]) {
        self.node = node
        let next = (map[node.id] ?? []).sorted(by: Self.byName)
        children = next.isEmpty ? nil : next.map { SidebarDevice(node: $0, children: map) }
    }
    static func byName(_ a: HardwareNode, _ b: HardwareNode) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
