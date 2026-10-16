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
    @Environment(\.mapScale) private var scale
    private var motionDisabled: Bool { reduceMotion || !store.animateConnections || store.activeMapKind != .physical }
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
                            MacIllustration(form: store.snapshot.formFactor).frame(width: 280 * scale, height: 250 * scale)
                        }.buttonStyle(.plain).help("Show Mac details and power readings")
                            .anchorPreference(key: FocusAnchors.self, value: .bounds) { ["mac": $0] }
                            .anchorPreference(key: SocketAnchors.self, value: .bounds) { ["mac": $0] }
                        Text("This Mac").font(.system(size: 14 * max(0.85, scale), weight: .medium))

                        Label("Front", systemImage: "arrow.down").font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.tertiary)
                        if store.snapshot.formFactor == .laptop {
                            Label(store.powerSample.chargingLabel, systemImage: store.powerStatus.externalPower == true ? "battery.100percent.bolt" : "battery.75percent")
                                .font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                            if let input = store.liveInput {
                                Text(input.label + " input").font(.system(size: 13 * max(0.85, scale), weight: .medium)).monospacedDigit().foregroundStyle(MapPowerStyle.incoming)
                            }
                            if let percent = store.powerSample.batteryPercent {
                                Text("Battery · \(percent)%").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                            }
                        }
                        if let output = store.totalOutput {
                            Text(String(format: "%.1f W total output", output))
                                .font(.system(size: 13 * max(0.85, scale), weight: .medium)).monospacedDigit().foregroundStyle(MapPowerStyle.outgoing)
                                .help("Sum of available measurements at Mac USB-C ports. Unreported ports are not included.")
                        } else {
                            Text("Output not reported").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 64 * scale)
                    column(.right).frame(width: columnWidth(.right) * scale).padding(.top, 64 * scale)
                }
                panel(.front)
            }.backgroundPreferenceValue(SocketAnchors.self) { anchors in
                GeometryReader { proxy in
                    ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motionDisabled || !hasLiveConnections)) { timeline in
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
                            let horizontal = socket.port.side == .left || socket.port.side == .right
                            let length: CGFloat = socket.isMagSafe || socket.isHDMI || socket.isUSBA ? 12 : 9
                            let size = CGSize(width: (horizontal ? 3 : length) * scale, height: (horizontal ? length : 3) * scale)
                            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                            let slot = Path(roundedRect: rect, cornerRadius: 1.2 * scale)
                            let look = appearance(for: socket)
                            var slotContext = context; slotContext.opacity = store.emphasis(for: socket)
                            slotContext.fill(slot, with: .color(.secondary.opacity(0.25)))
                            slotContext.stroke(slot, with: .color(.secondary.opacity(0.45)), lineWidth: 0.6 * scale)
                            if look.active {
                                CablePlugDrawing.draw(at: point, side: socket.port.side, magSafe: socket.isMagSafe, hdmi: socket.isHDMI, usbA: socket.isUSBA, scale: scale, context: &slotContext)
                            }
                        }
                    }.allowsHitTesting(false)
                }
            }
            if !projection.unplaced.isEmpty {
                VStack(alignment: .leading, spacing: 16 * scale) {
                    Text("Unmapped ports").font(.system(size: 16 * max(0.85, scale), weight: .semibold))
                    Text("Assign physical positions in Settings.").font(.system(size: 12 * max(0.85, scale))).foregroundStyle(.secondary)
                    ForEach(projection.unplaced) { connection in
                        VStack(alignment: .leading, spacing: 14 * scale) {
                            Button { if let id = connection.connector?.id { store.selection = .connector(id) } } label: {
                                HStack {
                                    Label(connection.connector?.label ?? "USB connection", systemImage: "cable.connector").font(.system(size: 13 * max(0.85, scale)))
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
                                Text(store.powerStatus.label).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)

                            }
                            if let connector = connection.connector, let output = store.output(for: connector.id) {
                                MapPowerBadge(outgoing: true, detail: output.label, scale: scale)
                            }
                            AttachmentView(roots: connection.devices)
                            ForEach(connection.connector?.links ?? []) { link in
                                Label(link.label, systemImage: link.symbol).font(.system(size: 12 * max(0.85, scale))).foregroundStyle(MapPalette.data)
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
        let unit = min(mac.width / 280, mac.height / 250)
        let origin = CGPoint(x: mac.minX + (mac.width - 280 * unit) / 2, y: mac.minY + (mac.height - 250 * unit) / 2)
        let point = MacDrawingGeometry.socket(form: store.snapshot.formFactor, side: socket.port.side, index: index, count: ordered.count, magSafe: socket.isMagSafe)
        return CGPoint(x: origin.x + point.x * unit, y: origin.y + point.y * unit)
    }
    private func socketEndpoints(_ socket: SocketConnection, mac: CGRect, card: CGRect) -> (CGPoint, CGPoint) {
        let point = socketPoint(socket, mac: mac)
        let distance = appearance(for: socket).active ? (socket.isMagSafe ? 9.0 : 12.0) * scale : 0
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
                Text("Unmapped connections").font(.system(size: 14 * max(0.85, scale), weight: .semibold))
                Text("Physical routes are unavailable for these connections.")
                    .font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                if store.powerStatus.externalPower == true && !hasPortPowerContract {
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "powerplug").font(.system(size: 22 * max(0.85, scale))).foregroundStyle(MapPalette.data)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(store.powerStatus.label).font(.system(size: 13 * max(0.85, scale), weight: .medium))
                            if let watts = store.powerStatus.adapterWatts {
                                Text("\(watts) W adapter rating").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                            }
                            Text("Input port unknown").font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(store.unassignedDisplays) { display in
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "display").font(.system(size: 22 * max(0.85, scale))).foregroundStyle(MapPalette.display)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Button(display.name) { store.selection = .display(display.id) }.buttonStyle(.plain).font(.system(size: 13 * max(0.85, scale), weight: .medium))
                            Text(display.mapLabel + " · port unknown").font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.secondary)
                        }
                    }.anchorPreference(key: FocusAnchors.self, value: .bounds) { ["display-\(display.id)": $0] }
                }
                ForEach(store.snapshot.thunderboltDevices) { device in
                    HStack(spacing: 12 * scale) {
                        Image(systemName: "bolt.horizontal").font(.system(size: 22 * max(0.85, scale))).foregroundStyle(MapPalette.data)
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(device.name).font(.system(size: 13 * max(0.85, scale), weight: .medium))
                            if let parent = store.snapshot.thunderboltDevices.first(where: { $0.id == device.parentID }) {
                                Text("Via " + parent.name).font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.secondary)
                            }
                            Text("Thunderbolt / USB4 · port unknown").font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.secondary)
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
                Text(side.label + " panel · left to right").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
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
        return max(338, CGFloat(counts.max() ?? 0) * 324 - 24)
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
        return 338 + CGFloat(levels) * 348
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
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motionDisabled || devices.isEmpty)) { timeline in
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
                    Text(socket.port.name).font(.system(size: 12 * max(0.85, scale), weight: .semibold))
                    Spacer(minLength: 0)
                    MapFunctionIcons(appearance: appearance(for: socket), scale: scale)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Show port details")
            if active {
                if !socket.devices.isEmpty { AttachmentView(roots: socket.devices, separatedIDs: separatedIDs) }
                else if !socket.isMagSafe {
                    Text(store.connectionLabel(for: socket)).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                }
                if store.receivesPower(socket) {
                    MapPowerBadge(scale: scale)
                    Text(store.powerSample.chargingLabel).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                }
                if let output = store.output(for: socket) {
                    MapPowerBadge(outgoing: true, detail: output.label, scale: scale)
                }
                if socket.isMagSafe || socket.devices.isEmpty, let watts = socket.connectors.filter({ $0.connectionActive != false }).compactMap(\.powerContractWatts).first {
                    Text("Power limit · \(watts) W").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                }
            } else if socket.connectors.isEmpty || socket.connectors.contains(where: { $0.connectionActive == nil }) {
                Text(socket.status).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
            }
        }.padding((active ? 16 + CGFloat(max(0, appearance(for: socket).colors.count - 1)) * 4 : 10) * scale)
            .frame(width: (active ? 300 : 155) * scale, alignment: .leading)
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
                }.padding(18 * scale).frame(width: 300 * scale, alignment: .leading)
                    .modifier(MapCardSurface(selected: store.selection == .device(node.id) || store.selection == .connection(node.id), scale: scale,
                        appearance: store.deviceAppearance(node), emphasized: store.emphasis(for: node.id) == 1, select: { store.selection = .device(node.id) }))
                    .anchorPreference(key: DeviceAnchors.self, value: .bounds) { [node.id: $0] }
            .anchorPreference(key: FocusAnchors.self, value: .bounds) { [node.id: $0] }

                    .help(node.displayID != nil ? "Display identity matched to the active DisplayPort transport. Route passes through this dock; further display adapters may not be enumerated." : store.attachmentHistory.laterAttachments.contains(node.id) ? "Observed joining an already connected hub during this session. Physical enclosure membership is not verified." : "Device connected downstream of the reported hub. Folded intermediate components remain available in Other components and Logical.")
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
                    .font(.system(size: 15 * max(0.85, scale), weight: .semibold)).foregroundStyle(MapPalette.data)

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
            }.font(.system(size: 10 * max(0.85, scale))).foregroundStyle(.secondary)
            ProgressView(value: volume.usedFraction).tint(MapPalette.data)
            if !compact || scale >= 0.8 {
                Text(compact ? "\(bytes(volume.availableBytes)) free" : "\(bytes(volume.usedBytes)) used of \(bytes(volume.totalBytes)) · \(bytes(volume.availableBytes)) free")
                    .font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack(spacing: 8 * scale) {
                Button { store.selectedID = node.id } label: {
                    HStack(alignment: .center, spacing: 12 * scale) {
                        if scale >= 0.6 {
                        Image(systemName: combined == nil ? node.symbol : "externaldrive").font(.system(size: 25 * max(0.85, scale), weight: .light)).foregroundStyle(node.displayID != nil ? MapPalette.display : MapPalette.data)
                            .frame(width: 42 * scale, height: 48 * scale).background(MapPalette.data.opacity(0.07), in: RoundedRectangle(cornerRadius: 10 * scale))
                        }
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(combined?.name ?? node.name).font(.system(size: 15 * max(0.85, scale), weight: .semibold)).lineLimit(scale >= 0.65 ? 2 : 1)
                            if scale >= 0.65 {
                                Text(node.isUSB4Tunnel == true ? "USB4 tunnel" : node.deviceDescription).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                            }

                            if let displayID = node.displayID {
                                Text(store.displayLabel(displayID) ?? "Display connected").font(.system(size: 11 * max(0.85, scale))).foregroundStyle(MapPalette.display)
                            } else {
                                Text(node.speed?.label ?? "Speed unavailable").lineLimit(1).font(.system(size: 12 * max(0.85, scale), weight: .medium, design: .monospaced)).foregroundStyle(MapPalette.data)
                            }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Show device details")
                if !children.isEmpty {
                    Button {
                        if store.collapsed.contains(node.id) { store.collapsed.remove(node.id) }
                        else { store.collapsed.insert(node.id) }
                    } label: { Image(systemName: store.collapsed.contains(node.id) ? "chevron.right" : "chevron.down").font(.system(size: 12 * max(0.85, scale))) }
                        .buttonStyle(.plain).help("Expand or collapse hub")
                }
            }
            .anchorPreference(key: DeviceAnchors.self, value: .bounds) { [node.id: $0] }
            .anchorPreference(key: FocusAnchors.self, value: .bounds) { [node.id: $0] }
            if let combined {
                Button("Drive details") { store.selectedID = combined.id }
                    .buttonStyle(.plain).font(.system(size: 10 * max(0.85, scale))).foregroundStyle(MapPalette.data)

            }
            if scale >= 0.55 {
                ForEach(store.snapshot.storage.filter { $0.deviceID == (combined?.id ?? node.id) }) { StorageUsageView(volume: $0) }
            }
            let additional = children.filter { !separatedIDs.contains($0.id) }
            if scale >= 0.6 && !store.collapsed.contains(node.id) && !additional.isEmpty {
                Button {
                    if store.expandedComponents.contains(node.id) { store.expandedComponents.remove(node.id) }
                    else { store.expandedComponents.insert(node.id) }
                } label: {
                    Label("Other components (\(additional.count))", systemImage: store.expandedComponents.contains(node.id) ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain).font(.system(size: 11 * max(0.85, scale))).foregroundStyle(.secondary)
                    .help("Presentation grouping only; these components are not necessarily built into the hub. Right-click a component or use its inspector to choose physical placement.")
                if store.expandedComponents.contains(node.id) {
                    VStack(alignment: .leading, spacing: 14 * scale) {
                        ForEach(additional) { child in
                            AnyView(DeviceBranch(node: child, visited: visited.union([node.id]), separatedIDs: separatedIDs))
                        }
                    }.padding(.leading, 14 * scale).overlay(alignment: .leading) {
                        Rectangle().fill(MapPalette.data.opacity(0.18)).frame(width: scale)
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

/// Canvas geometry and socket endpoints share one coordinate system.
private enum MacDrawingGeometry {
    static func chassis(_ form: MacFormFactor) -> CGRect {
        form == .laptop ? CGRect(x: 7, y: 42, width: 266, height: 199) : CGRect(x: 22, y: 10, width: 236, height: 230)
    }
    static func socket(form: MacFormFactor, side: PortSide, index: Int, count: Int, magSafe: Bool) -> CGPoint {
        let body = chassis(form)
        let fraction = CGFloat(index + 1) / CGFloat(max(1, count) + 1)
        let sideY: CGFloat
        if form == .laptop {
            let spacing = min(24, (body.height * 0.48 - 38) / CGFloat(max(1, count - 1)))
            sideY = body.minY + (magSafe ? 18 : 38 + CGFloat(index) * spacing)
        } else { sideY = body.minY + 20 + fraction * (body.height - 40) }
        let panelX = body.minX + 20 + fraction * (body.width - 40)
        switch side {
        case .left: return CGPoint(x: body.minX, y: sideY)
        case .right: return CGPoint(x: body.maxX, y: sideY)
        case .back: return CGPoint(x: panelX, y: body.minY)
        case .front: return CGPoint(x: panelX, y: body.maxY)
        }
    }
}

private struct MacIllustration: View {
    let form: MacFormFactor
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 280, size.height / 250)
            context.translateBy(x: (size.width - 280 * unit) / 2, y: (size.height - 250 * unit) / 2)
            context.scaleBy(x: unit, y: unit)
            func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path { Path(roundedRect: rect, cornerRadius: radius) }
            func gradient(_ colors: [Color], _ from: CGPoint, _ to: CGPoint) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
            }
            let silver = Color(white: colorScheme == .dark ? 0.73 : 0.92)
            let edge = Color(white: colorScheme == .dark ? 0.43 : 0.66)
            let laptop = form == .laptop
            let rect = MacDrawingGeometry.chassis(form)
            let chassis = rounded(rect, laptop ? 15 : 35)
            var shadow = context
            shadow.addFilter(.shadow(color: .black.opacity(0.20), radius: 9, x: 0, y: 7))
            shadow.fill(chassis, with: .color(edge))
            context.fill(chassis, with: gradient([silver, Color(white: 0.81), silver, edge], CGPoint(x: 0, y: 30), CGPoint(x: 290, y: 275)))
            context.stroke(chassis, with: .color(.white.opacity(0.75)), lineWidth: 1)
            context.stroke(rounded(rect.insetBy(dx: 1.7, dy: 1.7), laptop ? 14 : 34), with: .color(.black.opacity(0.15)), lineWidth: 0.6)
            if laptop {
                // A foreshortened display leaves the plan-view socket positions legible.
                let lidRect = CGRect(x: 10, y: 3, width: 260, height: 39)
                let lid = rounded(lidRect, 7)
                context.fill(lid, with: gradient([Color(white: 0.3), Color(white: 0.06)], CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 42)))
                context.stroke(lid, with: .color(.white.opacity(0.5)), lineWidth: 0.8)
                let display = CGRect(x: 17, y: 8, width: 246, height: 27)
                context.fill(rounded(display, 3), with: gradient([Color(red: 0.035, green: 0.09, blue: 0.18), Color(red: 0.12, green: 0.40, blue: 0.49), Color(red: 0.30, green: 0.68, blue: 0.68)], CGPoint(x: 17, y: 8), CGPoint(x: 263, y: 35)))
                var waves = context
                waves.clip(to: rounded(display, 3))
                for index in 0..<4 {
                    let offset = CGFloat(index) * 8
                    var wave = Path()
                    wave.move(to: CGPoint(x: 10, y: 38 + offset))
                    wave.addCurve(to: CGPoint(x: 278, y: 12 + offset), control1: CGPoint(x: 90, y: -14 + offset), control2: CGPoint(x: 180, y: 56 + offset))
                    waves.stroke(wave, with: .color(.white.opacity(0.10)), lineWidth: 5)
                }
                context.fill(rounded(CGRect(x: 133, y: 7, width: 14, height: 3), 1), with: .color(Color(white: 0.05)))
                context.fill(rounded(CGRect(x: 37, y: 41, width: 206, height: 5), 2), with: gradient([Color(white: 0.10), Color(white: 0.3)], CGPoint(x: 37, y: 41), CGPoint(x: 37, y: 46)))
                let keyboard = CGRect(x: 32, y: 57, width: 216, height: 98)
                context.fill(rounded(keyboard, 7), with: .color(Color(white: 0.075)))
                context.stroke(rounded(keyboard, 7), with: .color(.white.opacity(0.4)), lineWidth: 0.6)
                func key(_ rect: CGRect) {
                    let shape = rounded(rect, 2.5)
                    context.fill(shape, with: gradient([Color(white: 0.25), Color(white: 0.13)], CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)))
                    context.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 0.45)
                }
                for col in 0..<14 { key(CGRect(x: 37 + CGFloat(col) * 14.8, y: 62, width: 12.1, height: 9)) }
                let keyCounts = [10, 9, 7]
                for row in 0..<3 {
                    let y = 75 + CGFloat(row) * 18
                    let leading: CGFloat = row == 2 ? 27 : (row == 1 ? 23 : 18)
                    key(CGRect(x: 37, y: y, width: leading, height: 14))
                    var x = 40 + leading
                    for _ in 0..<keyCounts[row] {
                        key(CGRect(x: x, y: y, width: 14, height: 14)); x += 17
                    }
                    if x < 242 { key(CGRect(x: x, y: y, width: 243 - x, height: 14)) }
                }
                for col in 0..<3 { key(CGRect(x: 37 + CGFloat(col) * 18, y: 129, width: 15, height: 17)) }
                key(CGRect(x: 91, y: 129, width: 96, height: 17))
                for col in 0..<3 { key(CGRect(x: 190 + CGFloat(col) * 18, y: 129, width: 15, height: 17)) }
                let trackpad = CGRect(x: 73, y: 166, width: 134, height: 59)
                context.fill(rounded(trackpad, 6), with: gradient([.white.opacity(0.14), .black.opacity(0.035)], CGPoint(x: 73, y: 166), CGPoint(x: 207, y: 225)))
                context.stroke(rounded(trackpad, 6), with: .color(.black.opacity(0.25)), lineWidth: 0.7)
                context.stroke(rounded(trackpad.insetBy(dx: 0.8, dy: 0.8), 5), with: .color(.white.opacity(0.30)), lineWidth: 0.5)
                for y in stride(from: 63, through: 148, by: 3) {
                    for x in [18, 21, 24, 256, 259, 262] {
                        context.fill(Path(ellipseIn: CGRect(x: CGFloat(x), y: CGFloat(y), width: 0.7, height: 0.7)), with: .color(.black.opacity(0.38)))
                    }
                }
                context.fill(rounded(CGRect(x: 119, y: 236, width: 42, height: 3), 1.5), with: .color(.black.opacity(0.18)))
            } else {
                let top = rect.insetBy(dx: 5, dy: 5)
                context.stroke(rounded(top, 31), with: .color(.white.opacity(0.35)), lineWidth: 0.7)
                context.fill(rounded(CGRect(x: 53, y: 225, width: 174, height: 4), 2), with: .color(.black.opacity(0.22)))
                context.fill(Path(ellipseIn: CGRect(x: 230, y: 216, width: 2.5, height: 2.5)), with: .color(.white.opacity(0.95)))
            }
        }.accessibilityLabel(form == .laptop ? "Laptop viewed from above, screen hinge at the top" : "Desktop enclosure viewed from above, front at the bottom")
    }
}


/// A flat connector silhouette matches the diagram's visual language.
private enum CablePlugDrawing {
    static func draw(at point: CGPoint, side: PortSide, magSafe: Bool, hdmi: Bool, usbA: Bool, scale: CGFloat, context: inout GraphicsContext) {
        context.translateBy(x: point.x, y: point.y)
        let angle: Double = side == .left ? 180 : side == .back ? -90 : side == .front ? 90 : 0
        context.rotate(by: .degrees(angle)); context.scaleBy(x: scale, y: scale)
        let width: CGFloat = magSafe ? 6 : 9
        let height: CGFloat = magSafe || hdmi || usbA ? 12 : 8
        let head: Path
        if hdmi {
            head = Path { path in
                path.move(to: CGPoint(x: 0, y: -4))
                path.addLines([CGPoint(x: 2, y: -6), CGPoint(x: width, y: -6), CGPoint(x: width, y: 6), CGPoint(x: 2, y: 6), CGPoint(x: 0, y: 4)])
                path.closeSubpath()
            }
        } else {
            head = Path(roundedRect: CGRect(x: 0, y: -height / 2, width: width, height: height), cornerRadius: magSafe || usbA ? 1.5 : 2.5)
        }
        context.fill(head, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(head, with: .color(.secondary.opacity(0.65)), lineWidth: 0.8)
        var stem = Path(); stem.move(to: CGPoint(x: width, y: 0))
        stem.addLine(to: CGPoint(x: magSafe ? 9 : 12, y: 0))
        context.stroke(stem, with: .color(.secondary.opacity(0.65)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}

private enum ConnectionDrawing {
    static func stroke(_ path: Path, context: inout GraphicsContext, scale: CGFloat, phase: Double,
                       active: Bool, display: Bool, power: Bool, powerOutgoing: Bool = false, data: Bool = false, reduceMotion: Bool) {
        var layers: [(color: Color, direction: Double, power: Bool)] = []
        if display { layers.append((MapPalette.display, 1, false)) }
        if power { layers.append((powerOutgoing ? MapPowerStyle.outgoing : MapPowerStyle.incoming, powerOutgoing ? 1 : -1, true)) }
        if data { layers.append((MapPalette.data, 1, false)) }
        if layers.isEmpty { layers = [(active ? MapPalette.data : .secondary, 1, false)] }
        let motion = phase.truncatingRemainder(dividingBy: 29.0 / 24.0) * 24
        for (index, layer) in layers.enumerated() {
            let offset = (CGFloat(index) - CGFloat(layers.count - 1) / 2) * 5 * scale
            let track = offsetTrack(path, offset: offset)
            let width = (layer.power ? 3.2 : 1.8) * scale
            context.stroke(track, with: .color(layer.color.opacity(active ? 0.65 : 0.18)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            if active && !reduceMotion {
                context.stroke(track, with: .color(layer.color.opacity(0.95)), style: StrokeStyle(lineWidth: width, lineCap: .round,
                    dash: [4 * scale, 25 * scale], dashPhase: CGFloat(-motion * layer.direction) * scale))
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
