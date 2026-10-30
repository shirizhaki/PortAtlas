import SwiftUI
import PortAtlasCore

struct MapScale: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var mapScale: CGFloat { get { self[MapScale.self] } set { self[MapScale.self] = newValue } }
}
private struct SocketAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private struct DeviceAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct PhysicalMapView: View {
    var body: some View {
        MapViewport(kind: .physical) { PhysicalMapContent() }
    }
}

private struct PhysicalMapContent: View {
    @EnvironmentObject private var store: AtlasStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.mapScale) private var scale
    /// Wires animate only while this window is active: the whole map redraws per frame,
    /// so a background window stays still and idle.
    private var motionDisabled: Bool { reduceMotion || !store.animateConnections || store.activeMapKind != .physical || !appearsActive }
    private var hasLiveConnections: Bool { projection.sockets.contains { !$0.devices.isEmpty || $0.connectors.contains { $0.connectionActive == true } } }
    private var projection: PhysicalTopology { store.physicalTopology }
    private func sockets(on side: PortSide) -> [SocketConnection] { projection.sockets.filter { $0.port.side == side } }
    private var naturalWidth: CGFloat {
        max(columnWidth(.left) + columnWidth(.right) + 424, max(panelWidth(.front), panelWidth(.back)) + 64)
    }
    var body: some View { mapContent }
    private var mapContent: some View {
        VStack(spacing: 36 * scale) {
            VStack(spacing: 36 * scale) {
                panel(.back)
                HStack(alignment: .top, spacing: 40 * scale) {
                    column(.left).frame(width: columnWidth(.left) * scale)
                    VStack(spacing: 18 * scale) {
                        Button { store.selection = .mac } label: {
                            MacArtwork(product: store.macProduct).frame(width: MacArtworkGeometry.size.width * scale, height: MacArtworkGeometry.size.height * scale)
                        }.buttonStyle(.plain).help("Show Mac details and power readings")
                            .anchorPreference(key: FocusAnchors.self, value: .bounds) { ["mac": $0] }
                            .anchorPreference(key: SocketAnchors.self, value: .bounds) { ["mac": $0] }
                        // Name, orientation and one status line; live readings live in the toolbar and inspector.
                        VStack(spacing: 4 * scale) {
                            Text("This Mac").font(.system(size: 13 * scale, weight: .semibold))
                            if store.snapshot.formFactor == .laptop {
                                Text(store.powerSample.batteryPercent.map { "\(store.powerSample.chargingLabel) · \($0)%" } ?? store.powerSample.chargingLabel)
                                    .font(.system(size: 11 * scale)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Label("Front", systemImage: "arrow.down").font(.system(size: 10 * scale)).foregroundStyle(.tertiary)
                                .padding(.top, 6 * scale)
                        }
                    }.padding(.top, 64 * scale)
                    column(.right).frame(width: columnWidth(.right) * scale).padding(.top, 64 * scale)
                }
                panel(.front)
            }.backgroundPreferenceValue(SocketAnchors.self) { anchors in
                GeometryReader { proxy in
                    ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: motionDisabled || !hasLiveConnections)) { timeline in
                    Canvas { context, _ in
                        let phase = motionDisabled ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        guard let anchor = anchors["mac"] else { return }
                        let mac = proxy[anchor]
                        for socket in projection.sockets {
                            guard let anchor = anchors[socket.id.uuidString] else { continue }
                            let card = proxy[anchor]
                            let (a, b) = socketEndpoints(socket, mac: mac, card: card)
                            let horizontal = socket.port.side == .left || socket.port.side == .right
                            var path = Path(); path.move(to: a)
                            path.addCurve(to: b,
                                control1: horizontal ? CGPoint(x: (a.x + b.x) / 2, y: a.y) : CGPoint(x: a.x, y: (a.y + b.y) / 2),
                                control2: horizontal ? CGPoint(x: (a.x + b.x) / 2, y: b.y) : CGPoint(x: b.x, y: (a.y + b.y) / 2))
                            let powered = store.receivesPower(socket), display = store.carriesDisplay(socket)
                            let active = !socket.devices.isEmpty || socket.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty }
                            var wireContext = context; wireContext.opacity = store.emphasis(for: socket)
                            ConnectionDrawing.stroke(path, context: &wireContext, scale: scale, phase: phase,
                                active: active, display: display, power: powered || store.suppliesPower(socket), powerOutgoing: !powered && store.suppliesPower(socket), data: appearance(for: socket).data, reduceMotion: motionDisabled)
                        }
                    }.allowsHitTesting(false)
                    }
                    if let macAnchor = anchors["mac"] {
                        ForEach(projection.sockets) { socket in
                            if let anchor = anchors[socket.id.uuidString] {
                                let (a, b) = socketEndpoints(socket, mac: proxy[macAnchor], card: proxy[anchor])
                                ConnectionHitArea(path: curve(a, b, horizontal: socket.port.side == .left || socket.port.side == .right), label: "Connection to " + socket.port.name) {
                                    store.selection = .socket(socket.id)
                                }
                            }
                        }
                    }
                    }
                }
            }
            .overlayPreferenceValue(SocketAnchors.self) { anchors in
                GeometryReader { proxy in
                    Canvas { context, _ in
                        guard let macAnchor = anchors["mac"] else { return }
                        for socket in projection.sockets {
                            guard anchors[socket.id.uuidString] != nil else { continue }
                            let point = socketPoint(socket, mac: proxy[macAnchor])
                            var portContext = context; portContext.opacity = store.emphasis(for: socket)
                            PortDrawing.draw(portKind(socket), at: point, side: socket.port.side, plugged: appearance(for: socket).active,
                                             led: magSafeLight(socket), scale: scale, context: &portContext)
                        }
                    }.allowsHitTesting(false)
                }
            }
            if !projection.unplaced.isEmpty {
                VStack(alignment: .leading, spacing: 16 * scale) {
                    Text("Needs a Position").font(.system(size: 16 * scale, weight: .semibold))
                    Text("Use Match Ports to place these.").font(.system(size: 12 * scale)).foregroundStyle(.secondary)
                    ForEach(projection.unplaced) { connection in
                        VStack(alignment: .leading, spacing: 14 * scale) {
                            Button { if let id = connection.connector?.id { store.selection = .connector(id) } } label: {
                                HStack {
                                    Label(connection.connector?.label ?? "USB connection", systemImage: "cable.connector").font(.system(size: 13 * scale))
                                    Spacer(minLength: 0)
                                    MapFunctionIcons(appearance: MapConnectionAppearance(active: !connection.devices.isEmpty || connection.connector?.connectionActive == true,
                                        display: connection.connector?.links.contains { $0.isDisplay } == true,
                                        power: connection.connector.map { store.powerRoute?.connectorID == $0.id || store.output(for: $0.id) != nil } == true,
                                        powerOutgoing: connection.connector.map { store.output(for: $0.id) != nil } == true,
                                        data: connection.devices.contains { $0.displayID == nil }), scale: scale)
                                }

                            }.buttonStyle(.plain)

                            if let connector = connection.connector, let route = store.powerRoute, route.connectorID == connector.id {
                                MapPowerBadge(scale: scale)
                                Text(store.powerStatus.label).font(.system(size: 11 * scale)).foregroundStyle(.secondary)

                            }
                            if let connector = connection.connector, let output = store.output(for: connector.id) {
                                MapPowerBadge(outgoing: true, detail: output.label, scale: scale)
                            }
                            AttachmentView(roots: connection.devices)
                            ForEach(connection.connector?.links ?? []) { link in
                                Label(link.label, systemImage: link.symbol).font(.system(size: 12 * scale)).foregroundStyle(MapPalette.data)
                            }
                        }.padding(18 * scale).frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(MapCardSurface(scale: scale, appearance: MapConnectionAppearance(active: !connection.devices.isEmpty || connection.connector?.connectionActive == true, display: connection.connector?.links.contains { $0.isDisplay } == true,
                                power: connection.connector.map { store.powerRoute?.connectorID == $0.id || store.output(for: $0.id) != nil } == true,
                                powerOutgoing: connection.connector.map { store.output(for: $0.id) != nil } == true, data: connection.devices.contains { $0.displayID == nil }), select: {
                                    if let id = connection.connector?.id { store.selection = .connector(id) }
                                    else if let device = connection.devices.first { store.selection = .device(device.id) }
                                }))
                            .anchorPreference(key: FocusAnchors.self, value: .bounds) { [connection.id: $0] }
                    }
                }
            }
            systemConnections
        }.padding(32 * scale).frame(width: naturalWidth * scale).fixedSize(horizontal: false, vertical: true)
    }
    private func socketPoint(_ socket: SocketConnection, mac: CGRect) -> CGPoint {
        let ordered = sockets(on: socket.port.side).filter { !$0.isMagSafe }
        let index = ordered.firstIndex { $0.id == socket.id } ?? 0
        let design = MacArtworkGeometry.size
        let unit = min(mac.width / design.width, mac.height / design.height)
        let origin = CGPoint(x: mac.minX + (mac.width - design.width * unit) / 2, y: mac.minY + (mac.height - design.height * unit) / 2)
        let point = MacArtworkGeometry.socket(product: store.macProduct, side: socket.port.side, index: index, count: ordered.count, magSafe: socket.isMagSafe)
        return CGPoint(x: origin.x + point.x * unit, y: origin.y + point.y * unit)
    }
    private func socketEndpoints(_ socket: SocketConnection, mac: CGRect, card: CGRect) -> (CGPoint, CGPoint) {
        let point = socketPoint(socket, mac: mac)
        // A connected cable leaves from the end of its plug.
        let distance = appearance(for: socket).active ? PortDrawing.plugLength(portKind(socket)) * scale : 0
        let vector = socket.port.side == .left ? CGPoint(x: -1, y: 0) : socket.port.side == .right ? CGPoint(x: 1, y: 0) : socket.port.side == .back ? CGPoint(x: 0, y: -1) : CGPoint(x: 0, y: 1)
        let a = CGPoint(x: point.x + vector.x * distance, y: point.y + vector.y * distance)
        let b: CGPoint
        switch socket.port.side {
        case .left:
            b = CGPoint(x: card.maxX, y: card.midY)
        case .right:
            b = CGPoint(x: card.minX, y: card.midY)
        case .back:
            b = CGPoint(x: card.midX, y: card.maxY)
        default:
            b = CGPoint(x: card.midX, y: card.minY)
        }
        return (a, b)
    }
    private func appearance(for socket: SocketConnection) -> MapConnectionAppearance { store.socketAppearance(socket) }
    private func portKind(_ socket: SocketConnection) -> PortDrawing.Kind {
        socket.isMagSafe ? .magSafe : socket.isHDMI ? .hdmi : socket.isUSBA ? .usbA : .usbC
    }
    /// MagSafe's light: amber while the battery charges, green otherwise, as on the real plug.
    private func magSafeLight(_ socket: SocketConnection) -> Color? {
        guard socket.isMagSafe, store.receivesPower(socket) else { return nil }
        return store.powerStatus.isCharging == true ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen)
    }
    private func curve(_ a: CGPoint, _ b: CGPoint, horizontal: Bool) -> Path {
        var path = Path(); path.move(to: a)
        path.addCurve(to: b, control1: horizontal ? CGPoint(x: (a.x + b.x) / 2, y: a.y) : CGPoint(x: a.x, y: (a.y + b.y) / 2),
            control2: horizontal ? CGPoint(x: (a.x + b.x) / 2, y: b.y) : CGPoint(x: b.x, y: (a.y + b.y) / 2))
        return path
    }
    private var hasPortPowerContract: Bool { store.powerRoute != nil }
    @ViewBuilder private var systemConnections: some View {
        if !store.unassignedDisplays.isEmpty || !store.snapshot.thunderboltDevices.isEmpty || (store.powerStatus.externalPower == true && !hasPortPowerContract) {
            VStack(alignment: .leading, spacing: 16 * scale) {
                Text("Needs a Position").font(.system(size: 14 * scale, weight: .semibold))
                Text("The port for these connections isn't known.")
                    .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                if store.powerStatus.externalPower == true && !hasPortPowerContract {
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "powerplug").font(.system(size: 22 * scale)).foregroundStyle(MapPalette.Graphic.data)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(store.powerStatus.label).font(.system(size: 13 * scale, weight: .medium))
                            if let watts = store.powerStatus.adapterWatts {
                                Text("\(watts) W adapter rating").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                            }
                            Text("Input port unknown").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(store.unassignedDisplays) { display in
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "display").font(.system(size: 22 * scale)).foregroundStyle(MapPalette.Graphic.display)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Button(display.name) { store.selection = .display(display.id) }.buttonStyle(.plain).font(.system(size: 13 * scale, weight: .medium))
                            Text(display.mapLabel + " · port unknown").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                        }
                    }.anchorPreference(key: FocusAnchors.self, value: .bounds) { ["display-\(display.id)": $0] }
                }
                ForEach(store.snapshot.thunderboltDevices) { device in
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "bolt.horizontal").font(.system(size: 22 * scale)).foregroundStyle(MapPalette.Graphic.data)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(device.name).font(.system(size: 13 * scale, weight: .medium))
                            if let parent = store.snapshot.thunderboltDevices.first(where: { $0.id == device.parentID }) {
                                Text("Via " + parent.name).font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                            }
                            Text("Thunderbolt / USB4 · port unknown").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(20 * scale).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 17 * scale))
        }
    }
    private func column(_ side: PortSide) -> some View {
        VStack(alignment: side == .left ? .trailing : .leading, spacing: 32 * scale) {
            ForEach(sockets(on: side)) { socketCard($0) }
        }.frame(maxWidth: .infinity, alignment: side == .left ? .trailing : .leading)
    }
    @ViewBuilder private func panel(_ side: PortSide) -> some View {
        if !sockets(on: side).isEmpty {
            VStack(alignment: .leading, spacing: 12 * scale) {
                Text(side.label + " panel · left to right").font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 24 * scale) { ForEach(sockets(on: side)) { socketCard($0).frame(width: verticalWidth($0) * scale) } }
            }
        }
    }
    private func downstreamDevices(_ socket: SocketConnection) -> [HardwareNode] {
        let rootIDs = Set(socket.devices.map(\.id))
        return store.snapshot.nodes.filter { node in
            guard (node.kind == .device || node.kind == .hub),
                  store.presentation.shouldSeparate(node, automatically: node.transport != nil || node.interfaceClasses?.contains(8) == true || store.attachmentHistory.laterAttachments.contains(node.id)),
                  store.snapshot.connectionParent(of: node.id)?.kind == .hub else { return false }
            guard !store.presentation.combinedStorageIDs.contains(node.id) else { return false }
            let ancestors = store.snapshot.ancestry(of: node.id).dropLast()
            return ancestors.contains(where: { rootIDs.contains($0.id) }) &&
                !ancestors.contains(where: { store.collapsed.contains($0.id) })
        }
    }
    private func depth(_ node: HardwareNode, among ids: Set<String>) -> Int {
        store.snapshot.ancestry(of: node.id).dropLast().filter { ids.contains($0.id) }.count + 1
    }
    private func verticalWidth(_ socket: SocketConnection) -> CGFloat {
        let nodes = downstreamDevices(socket), ids = Set(nodes.map(\.id))
        let counts = Dictionary(grouping: nodes, by: { depth($0, among: ids) }).values.map(\.count)
        return max(MapMetrics.card + 38, CGFloat(counts.max() ?? 0) * (MapMetrics.card + 24) - 24)
    }
    private func panelWidth(_ side: PortSide) -> CGFloat {
        let ports = sockets(on: side)
        return ports.reduce(CGFloat.zero) { $0 + verticalWidth($1) } + CGFloat(max(0, ports.count - 1)) * 24
    }
    private func columnWidth(_ side: PortSide) -> CGFloat {
        let levels = sockets(on: side).map { socket -> Int in
            let nodes = downstreamDevices(socket), ids = Set(nodes.map(\.id))
            return nodes.map { depth($0, among: ids) }.max() ?? 0
        }.max() ?? 0
        return MapMetrics.card + 38 + CGFloat(levels) * (MapMetrics.card + 48)
    }
    private func socketCard(_ socket: SocketConnection) -> some View {
        let devices = downstreamDevices(socket)
        let separatedIDs = Set(devices.map(\.id))
        let levels = devices.map { depth($0, among: separatedIDs) }.max() ?? 0
        let horizontal = socket.port.side == .left || socket.port.side == .right
        let reverse = socket.port.side == .left || socket.port.side == .back
        let layout: AnyLayout = horizontal ? AnyLayout(HStackLayout(alignment: .center, spacing: 48 * scale)) : AnyLayout(VStackLayout(alignment: .center, spacing: 48 * scale))
        let order = reverse ? Array((0...levels).reversed()) : Array(0...levels)
        return layout {
            ForEach(order, id: \.self) { level in
                if level == 0 { hubCard(socket, separatedIDs: separatedIDs) }
                else {
                    let peers: AnyLayout = horizontal ? AnyLayout(VStackLayout(spacing: 24 * scale)) : AnyLayout(HStackLayout(spacing: 24 * scale))
                    peers {
                        ForEach(devices.filter { depth($0, among: separatedIDs) == level }) { node in
                            downstreamCard(node, separatedIDs: separatedIDs)
                        }
                    }
                }
            }
        }.backgroundPreferenceValue(DeviceAnchors.self) { anchors in
            GeometryReader { proxy in
                ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: motionDisabled || devices.isEmpty)) { timeline in
                Canvas { context, _ in
                    let phase = motionDisabled ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    for node in devices {
                        guard let parentID = store.snapshot.ancestry(of: node.id).dropLast().reversed().first(where: { anchors[$0.id] != nil })?.id, let from = anchors[parentID], let to = anchors[node.id] else { continue }
                        let parent = proxy[from], child = proxy[to]
                        let start: CGPoint; let end: CGPoint
                        switch socket.port.side {
                        case .left: start = CGPoint(x: parent.minX, y: parent.midY); end = CGPoint(x: child.maxX, y: child.midY)
                        case .right: start = CGPoint(x: parent.maxX, y: parent.midY); end = CGPoint(x: child.minX, y: child.midY)
                        case .back: start = CGPoint(x: parent.midX, y: parent.minY); end = CGPoint(x: child.midX, y: child.maxY)
                        case .front: start = CGPoint(x: parent.midX, y: parent.maxY); end = CGPoint(x: child.midX, y: child.minY)
                        }
                        var path = Path(); path.move(to: start)
                        let midX = (start.x + end.x) / 2, midY = (start.y + end.y) / 2
                        path.addCurve(to: end,
                            control1: horizontal ? CGPoint(x: midX, y: start.y) : CGPoint(x: start.x, y: midY),
                            control2: horizontal ? CGPoint(x: midX, y: end.y) : CGPoint(x: end.x, y: midY))
                        var wireContext = context; wireContext.opacity = store.emphasis(for: node.id)
                        ConnectionDrawing.stroke(path, context: &wireContext, scale: scale, phase: phase,
                            active: true, display: node.displayID != nil, power: false, data: node.displayID == nil, reduceMotion: motionDisabled)
                    }
                }.allowsHitTesting(false)
                }
                ForEach(devices) { node in
                    if let parentID = store.snapshot.ancestry(of: node.id).dropLast().reversed().first(where: { anchors[$0.id] != nil })?.id,
                       let from = anchors[parentID], let to = anchors[node.id] {
                        let path = downstreamCurve(parent: proxy[from], child: proxy[to], side: socket.port.side)
                        ConnectionHitArea(path: path, label: "Connection to " + node.name) { store.selection = .connection(node.id) }
                    }
                }
                }
            }
        }
    }
    private func downstreamCurve(parent: CGRect, child: CGRect, side: PortSide) -> Path {
        let start: CGPoint, end: CGPoint
        switch side {
        case .left: start = CGPoint(x: parent.minX, y: parent.midY); end = CGPoint(x: child.maxX, y: child.midY)
        case .right: start = CGPoint(x: parent.maxX, y: parent.midY); end = CGPoint(x: child.minX, y: child.midY)
        case .back: start = CGPoint(x: parent.midX, y: parent.minY); end = CGPoint(x: child.midX, y: child.maxY)
        case .front: start = CGPoint(x: parent.midX, y: parent.maxY); end = CGPoint(x: child.midX, y: child.minY)
        }
        return curve(start, end, horizontal: side == .left || side == .right)
    }
    private func hubCard(_ socket: SocketConnection, separatedIDs: Set<String>) -> some View {
        let active = !socket.devices.isEmpty || socket.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty }
        return VStack(alignment: .leading, spacing: 12 * scale) {
            Button { store.selection = .socket(socket.id) } label: {
                HStack(spacing: 8 * scale) {
                    Image(systemName: socket.isMagSafe ? "powerplug" : socket.isHDMI ? "display" : "cable.connector").foregroundStyle(.secondary)
                    Text(socket.port.name).font(.system(size: 12 * scale, weight: .semibold))
                    Spacer(minLength: 0)
                    MapFunctionIcons(appearance: appearance(for: socket), scale: scale)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Show port details")
            if active {
                if !socket.devices.isEmpty { AttachmentView(roots: socket.devices, separatedIDs: separatedIDs) }
                // One status line per card: a charger shows only its live power; details are in the inspector.
                else if !socket.isMagSafe && !store.receivesPower(socket) {
                    Text(store.connectionLabel(for: socket)).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                }
                if store.receivesPower(socket) {
                    MapPowerBadge(detail: store.liveInput?.label, scale: scale)
                }
                if let output = store.output(for: socket) {
                    MapPowerBadge(outgoing: true, detail: output.label, scale: scale)
                }
            } else if socket.connectors.isEmpty || socket.connectors.contains(where: { $0.connectionActive == nil }) {
                Text(socket.status).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
        }.padding((active ? 14 : 10) * scale)
            .frame(width: (active ? MapMetrics.card : 140) * scale, alignment: .leading)
            .modifier(MapCardSurface(selected: store.selection == .socket(socket.id), subdued: !active, scale: scale, appearance: appearance(for: socket), emphasized: store.emphasis(for: socket) == 1, select: { store.selection = .socket(socket.id) }))

            .anchorPreference(key: SocketAnchors.self, value: .bounds) { [socket.id.uuidString: $0] }
            .anchorPreference(key: FocusAnchors.self, value: .bounds) { anchors in
                var result = [socket.id.uuidString: anchors]
                for connector in socket.connectors { result[connector.id] = anchors }
                return result
            }
    }
    private func downstreamCard(_ node: HardwareNode, separatedIDs: Set<String>) -> some View {
                VStack(alignment: .leading, spacing: 10 * scale) {
                    HStack {
                        Spacer(minLength: 0)
                        MapFunctionIcons(appearance: store.deviceAppearance(node), scale: scale)
                    }
                    DeviceBranch(node: node, visited: [], separatedIDs: separatedIDs)
                }.padding(14 * scale).frame(width: MapMetrics.card * scale, alignment: .leading)
                    .modifier(MapCardSurface(selected: store.selection == .device(node.id) || store.selection == .connection(node.id), scale: scale,
                        appearance: store.deviceAppearance(node), emphasized: store.emphasis(for: node.id) == 1, select: { store.selection = .device(node.id) }))
                    .anchorPreference(key: DeviceAnchors.self, value: .bounds) { [node.id: $0] }
            .anchorPreference(key: FocusAnchors.self, value: .bounds) { [node.id: $0] }

    }

}

/// Companion branches share a compact presentation, without asserting enclosure boundaries.
private struct AttachmentView: View {
    @Environment(\.mapScale) private var scale
    let roots: [HardwareNode]
    var separatedIDs: Set<String> = []
    var body: some View {
        if roots.count > 1 {
            VStack(alignment: .leading, spacing: 16 * scale) {
                Label("USB branches", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary)

                ForEach(roots.sorted { ($0.speed?.megabitsPerSecond ?? 0) > ($1.speed?.megabitsPerSecond ?? 0) }) {
                    DeviceBranch(node: $0, visited: [], separatedIDs: separatedIDs)
                }
            }.padding(14 * scale).background(MapPalette.data.opacity(0.035), in: RoundedRectangle(cornerRadius: 12 * scale))
        } else {
            ForEach(roots) { DeviceBranch(node: $0, visited: [], separatedIDs: separatedIDs) }
        }
    }
}

struct StorageUsageView: View {
    @Environment(\.mapScale) private var scale
    let volume: StorageVolume
    var compact = true
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack {
                Text(volume.name).lineLimit(1)
                Spacer()
                Text("\(Int(volume.usedFraction * 100))% used").monospacedDigit()
            }.font(.system(size: 10 * scale)).foregroundStyle(.secondary)
            // Drawn in SwiftUI: the map renders through drawingGroup, which cannot host AppKit controls.
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(MapPalette.Graphic.data).frame(width: max(proxy.size.height, proxy.size.width * volume.usedFraction))
                    }
                }
                .frame(height: 5 * scale)
            if !compact {
                Text(compact ? "\(bytes(volume.availableBytes)) free" : "\(bytes(volume.usedBytes)) used of \(bytes(volume.totalBytes)) · \(bytes(volume.availableBytes)) free")
                    .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct DeviceBranch: View {
    @Environment(\.mapScale) private var scale
    @EnvironmentObject private var store: AtlasStore
    let node: HardwareNode
    let visited: Set<String>
    var separatedIDs: Set<String> = []
    private var combined: HardwareNode? { store.presentation.combinedStorage(for: node) }
    private var children: [HardwareNode] {
        store.snapshot.connectionChildren(of: node.id).filter {
            ($0.kind == .device || $0.kind == .hub) && !visited.contains($0.id) && $0.id != node.id && $0.id != combined?.id
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(spacing: 8 * scale) {
                Button { store.selectedID = node.id } label: {
                    HStack(alignment: .center, spacing: 10 * scale) {
                        // A role-tinted tile, like the system's tinted icon tiles, carries the connection role.
                        let role = node.displayID != nil ? MapPalette.Graphic.display : MapPalette.Graphic.data
                        Image(systemName: combined == nil ? node.symbol : "externaldrive").font(.system(size: 17 * scale, weight: .regular)).foregroundStyle(role)
                            .frame(width: 32 * scale, height: 32 * scale).background(role.opacity(0.14), in: RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                        VStack(alignment: .leading, spacing: 2 * scale) {
                            Text(combined?.name ?? node.name).font(.system(size: 13 * scale, weight: .semibold)).lineLimit(2)
                            Text(node.displayID != nil ? "Display" : node.isUSB4Tunnel == true ? "USB4 tunnel" : node.deviceDescription).font(.system(size: 11 * scale)).foregroundStyle(.secondary)

                            if let displayID = node.displayID {
                                Text(store.displayLabel(displayID) ?? "Display connected").font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary)
                            } else {
                                Text(node.speed?.label ?? "Speed unavailable").lineLimit(1).font(.system(size: 11 * scale, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Show device details")
                if !children.isEmpty {
                    Button {
                        if store.collapsed.contains(node.id) { store.collapsed.remove(node.id) }
                        else { store.collapsed.insert(node.id) }
                    } label: { Image(systemName: store.collapsed.contains(node.id) ? "chevron.right" : "chevron.down").font(.system(size: 12 * scale)) }
                        .buttonStyle(.plain).help("Expand or collapse hub")
                }
            }
            .anchorPreference(key: DeviceAnchors.self, value: .bounds) { [node.id: $0] }
            .anchorPreference(key: FocusAnchors.self, value: .bounds) { [node.id: $0] }
            if let combined {
                Button("Drive details") { store.selectedID = combined.id }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.system(size: 11 * scale))

            }
            ForEach(store.snapshot.storage.filter { $0.deviceID == (combined?.id ?? node.id) }) { StorageUsageView(volume: $0) }
            let additional = children.filter { !separatedIDs.contains($0.id) }
            if !store.collapsed.contains(node.id) && !additional.isEmpty {
                Button {
                    if store.expandedComponents.contains(node.id) { store.expandedComponents.remove(node.id) }
                    else { store.expandedComponents.insert(node.id) }
                } label: {
                    Label("Other components (\(additional.count))", systemImage: store.expandedComponents.contains(node.id) ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain).font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                    .help("Right-click a component to show it as its own device")
                if store.expandedComponents.contains(node.id) {
                    VStack(alignment: .leading, spacing: 14 * scale) {
                        ForEach(additional) { child in
                            AnyView(DeviceBranch(node: child, visited: visited.union([node.id]), separatedIDs: separatedIDs))
                        }
                    }.padding(.leading, 14 * scale).overlay(alignment: .leading) {
                        Rectangle().fill(MapPalette.Graphic.data.opacity(0.3)).frame(width: scale)
                    }
                }
            }

        }.contextMenu {
            if store.canPlaceComponent(node) {
                Button("Show as separate accessory") { store.setPlacement(.separate, for: node) }
                Button("Group as dock component") { store.setPlacement(.grouped, for: node) }
                Divider()
                Button("Use automatic placement") { store.setPlacement(.automatic, for: node) }
            }
        }
    }
}

/// Shared map dimensions, in unscaled map points.
enum MapMetrics {
    /// Width of a connected socket card and of each downstream device card.
    static let card: CGFloat = 260
}

private enum ConnectionDrawing {
    static func stroke(_ path: Path, context: inout GraphicsContext, scale: CGFloat, phase: Double,
                       active: Bool, display: Bool, power: Bool, powerOutgoing: Bool = false, data: Bool = false, reduceMotion: Bool) {
        // Wires are graphics, not text, so they use the vivid system hues in both appearances.
        var layers: [(color: Color, direction: Double, power: Bool)] = []
        if display { layers.append((MapPalette.Graphic.display, 1, false)) }
        if power { layers.append((powerOutgoing ? MapPalette.Graphic.outgoing : MapPalette.Graphic.incoming, powerOutgoing ? 1 : -1, true)) }
        if data { layers.append((MapPalette.Graphic.data, 1, false)) }
        if layers.isEmpty { layers = [(active ? MapPalette.Graphic.data : .secondary, 1, false)] }
        let light = context.environment.colorScheme == .light
        let motion = phase.truncatingRemainder(dividingBy: 29.0 / 24.0) * 24
        // A canvas-colored casing under the bundle keeps crossings and card edges clean, as in Maps.
        if active {
            let bundle = (CGFloat(layers.count - 1) * 3.5 + (layers.contains { $0.power } ? 3 : 2) + 4) * scale
            context.stroke(path, with: .color(MapPalette.canvas), style: StrokeStyle(lineWidth: bundle, lineCap: .round))
        }
        for (index, layer) in layers.enumerated() {
            let offset = (CGFloat(index) - CGFloat(layers.count - 1) / 2) * 3.5 * scale
            let track = offsetTrack(path, offset: offset)
            // Light mode needs a little more weight to hold its own on a bright canvas.
            let width = (layer.power ? (light ? 3 : 2.4) : (light ? 2 : 1.4)) * scale
            // A soft track in the role color with saturated pulses travelling along it.
            context.stroke(track, with: .color(layer.color.opacity(active ? (light ? 0.4 : 0.55) : 0.2)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            if active && !reduceMotion {
                context.stroke(track, with: .color(layer.color), style: StrokeStyle(lineWidth: width, lineCap: .round,
                    dash: [(light ? 9 : 4) * scale, (light ? 20 : 25) * scale], dashPhase: CGFloat(-motion * layer.direction) * scale))
            } else if active {
                context.stroke(track, with: .color(layer.color.opacity(0.85)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    /// Offset the curve along its normal, converging at the two physical endpoints.
    /// All tracks remain one cable and share the existing selection hit area.
    private static func offsetTrack(_ path: Path, offset: CGFloat) -> Path {
        guard offset != 0 else { return path }
        var result = Path()
        var start = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let point): start = point; result.move(to: point)
            case .curve(let end, let c1, let c2):
                for step in 1...64 {
                    let t = CGFloat(step) / 64, u = 1 - t
                    let point = CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                        y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)
                    let dx = 3*u*u*(c1.x-start.x) + 6*u*t*(c2.x-c1.x) + 3*t*t*(end.x-c2.x)
                    let dy = 3*u*u*(c1.y-start.y) + 6*u*t*(c2.y-c1.y) + 3*t*t*(end.y-c2.y)
                    let length = hypot(dx, dy)
                    let ramp = min(1, min(t, u) * 8)
                    let taper = ramp * ramp * (3 - 2 * ramp)
                    let distance = length > 0 ? offset * taper / length : 0
                    result.addLine(to: CGPoint(x: point.x - dy * distance, y: point.y + dx * distance))
                }
                start = end
            case .line(let point): result.addLine(to: point); start = point
            case .quadCurve(let end, let control): result.addQuadCurve(to: end, control: control); start = end
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
    }
}

struct ConnectionHitArea: View {
    let path: Path
    let label: String
    let select: () -> Void
    var body: some View {
        path.stroke(Color.clear, lineWidth: 18)
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 18)))
            .anchorPreference(key: WireInteractionAreas.self, value: .bounds) { [WireInteractionArea(path: path.strokedPath(StrokeStyle(lineWidth: 18)), bounds: $0)] }
            .onTapGesture(perform: select)
            .accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { select() }
    }
}
