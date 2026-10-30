import SwiftUI
import PortAtlasCore

/// The inspector. Each item gets a plain-language summary first; everything technical sits in
/// one Technical Details section at the bottom, without explanations.
struct DeviceDetailView: View {
    @EnvironmentObject private var store: AtlasStore

    // MARK: What is selected

    private var node: HardwareNode? {
        switch store.selection {
        case .device(let id), .connection(let id): return store.snapshot.node(id)
        case .display(let id): return store.snapshot.nodes.first { $0.displayID == id }
        default: return nil
        }
    }
    private var display: DisplayDevice? {
        if case .display(let id) = store.selection { return store.displays.first { $0.id == id } }
        return node?.displayID.flatMap { id in store.displays.first { $0.id == id } }
    }
    /// A port is selected directly, never inferred from a device.
    private var socket: SocketConnection? {
        switch store.selection {
        case .socket(let id): return store.physicalTopology.sockets.first { $0.id == id }
        case .connector(let id): return store.physicalTopology.sockets.first { $0.connectors.contains { $0.id == id } }
        default: return nil
        }
    }
    private var portConnectors: [HardwareConnector] {
        if let socket { return socket.connectors }
        if case .connector(let id) = store.selection { return store.snapshot.connectors.filter { $0.id == id } }
        return []
    }
    private var isPort: Bool { socket != nil || !portConnectors.isEmpty }

    var body: some View {
        Form {
            header
            if let display { displaySections(display) }
            else if let node { nodeSections(node) }
            else if isPort { portSections }
            else { macSections }
        }
        .formStyle(.grouped)
    }

    // MARK: Header

    private var header: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: headerSymbol).font(.title2).foregroundStyle(.secondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(headerSummary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(.vertical, 2)
        }
    }
    private var headerSymbol: String {
        if display != nil { return "display" }
        if let node { return node.symbol }
        if let socket { return socket.isMagSafe ? "powerplug" : socket.isHDMI ? "tv" : "cable.connector" }
        if isPort { return "cable.connector" }
        return store.macProduct.symbol
    }
    private var headerTitle: String {
        if let display { return display.name }
        if let node { return store.mapTitle(for: node) }
        if let socket { return socket.port.name }
        return portConnectors.first?.label ?? store.macName
    }
    private var headerSummary: String {
        if let display { return display.mapLabel }
        if let node { return nodeSummary(node) }
        if let socket { return isActive(socket) ? store.connectionLabel(for: socket) : "Nothing connected" }
        if isPort { return portConnectors.contains { $0.connectionActive == true } ? "Connected" : "Nothing connected" }
        return store.powerSample.chargingLabel
    }

    // MARK: This Mac

    @ViewBuilder private var macSections: some View {
        Section("Power") {
            if let input = store.liveInput {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Power in") {
                        Text(input.label).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(MapPowerStyle.incoming)
                    }
                    PowerGraph(samples: store.powerHistory.samples).frame(height: 64)
                }
            }
            if let percent = store.powerSample.batteryPercent { row("Battery", "\(percent)%") }
            if let charger = chargerDescription { row("Charger", charger) }
            if let route = store.powerRoute {
                LabeledContent("Charging through") {
                    Button(portName(for: route.connectorID)) { store.selection = .connector(route.connectorID) }.buttonStyle(.link)
                }.help("Inferred from the port's negotiated power contract.")
            }
            if let total = store.totalOutput {
                row("Powering accessories", String(format: "%.1f W", total))
                    .help("Measured at the Mac's ports. Ports that don't report are not included.")
            }
        }
        technicalDetails {
            if let name = store.snapshot.productName { row("Model", name) }
            row("Identifier", store.snapshot.modelIdentifier)
            if let voltage = store.powerSample.inputVoltage, voltage.isFresh(at: Date()) { row("Input voltage", voltage.label) }
            if let current = store.powerSample.inputCurrent, current.isFresh(at: Date()) { row("Input current", current.label) }
            if let battery = store.powerSample.battery, battery.isFresh(at: Date()) {
                row(battery.value < 0 ? "Battery discharge" : "Battery charge", String(format: "%.1f W", abs(battery.value)))
            }
            if let source = store.liveInput?.source { row("Reading source", source) }
        }
    }
    private var chargerDescription: String? {
        guard store.powerStatus.externalPower == true else { return nil }
        let parts = [store.powerStatus.adapterWatts.map { "\($0) W" }, store.powerSample.adapterName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Port

    @ViewBuilder private var portSections: some View {
        Section("Connection") {
            if let socket {
                row("Supports", socket.isMagSafe ? "MagSafe charging" : store.capabilityLabel(for: socket.port))
                if socket.devices.isEmpty {
                    if isActive(socket), !socket.isMagSafe { row("Connected", store.connectionLabel(for: socket)) }
                } else {
                    ForEach(socket.devices) { device in
                        LabeledContent("Connected") {
                            Button(store.mapTitle(for: device)) { store.selection = .device(device.id) }.buttonStyle(.link)
                        }
                    }
                }
            }
            ForEach(portConnectors) { connector in
                if let cable = connector.cable, connector.connectionActive == true { row("Cable", cable.productType) }
            }
        }
        if portConnectors.contains(where: { powerFacts($0) }) {
            Section("Power") {
                ForEach(portConnectors) { connector in
                    if connector.id == store.powerRoute?.connectorID {
                        LabeledContent("Charging this Mac") {
                            Text(store.liveInput?.label ?? "Yes").monospacedDigit().foregroundStyle(MapPowerStyle.incoming)
                        }
                    }
                    if let output = store.output(for: connector.id) {
                        LabeledContent("Powering accessory") {
                            Text(output.label).monospacedDigit().foregroundStyle(MapPowerStyle.outgoing)
                        }.help("Measured at the Mac's port.")
                    }
                    if let contract = connector.powerContractWatts, connector.connectionActive != false {
                        row("Charger limit", "\(contract) W").help("The maximum the charger agreed to supply, not what is being drawn.")
                    }
                }
            }
        }
        technicalDetails {
            ForEach(portConnectors) { connector in
                row("Connector", connector.label)
                if let mv = connector.power?.voltageMillivolts { row("Negotiated voltage", String(format: "%.1f V", Double(mv) / 1000)) }
                if let ma = connector.power?.currentMilliamps { row("Negotiated current", String(format: "%.2f A", Double(ma) / 1000)) }
                if let watts = connector.power?.advertisedWatts, connector.connectionActive != false { row("Charger maximum", "\(watts) W") }
                if let revision = connector.cable?.pdRevision, connector.connectionActive == true { row("Cable PD revision", String(revision)) }
                if let output = store.output(for: connector.id) {
                    row("Output", String(format: "%.2f V · %.2f A", output.volts, output.amps))
                    if let limit = output.configuredWatts { row("Output limit", String(format: "%g W", limit)) }
                }
                ForEach(connector.links) { link in row(link.label.replacingOccurrences(of: " link active", with: " link"), link.detail ?? "Active") }
                if !connector.laneDetails.isEmpty { row("Lanes", connector.laneDetails.joined(separator: "\n")) }
            }
            if let socket, !socket.isMagSafe { row("Support source", store.capabilitySource(for: socket.port)) }
        }
    }
    private func powerFacts(_ connector: HardwareConnector) -> Bool {
        connector.id == store.powerRoute?.connectorID || store.output(for: connector.id) != nil ||
            (connector.powerContractWatts != nil && connector.connectionActive != false)
    }

    // MARK: Device, hub, branch or controller

    @ViewBuilder private func nodeSections(_ node: HardwareNode) -> some View {
        Section {
            if node.kind == .device || node.kind == .hub {
                if let speed = node.speed {
                    row("Speed", speed.label).help("The connection's link rate, not measured transfer speed.")
                }
                if let manufacturer = node.manufacturer { row("Maker", manufacturer) }
            }
            connectedTo(node)
            let children = store.snapshot.connectionChildren(of: node.id)
            if !children.isEmpty { row("Devices behind it", "\(children.count)") }
            if store.canPlaceComponent(node) {
                Picker("Show on map", selection: Binding(get: { store.presentation.placement(for: node) }, set: { store.setPlacement($0, for: node) })) {
                    Text("Automatically").tag(ComponentPlacement.automatic)
                    Text("Inside the dock").tag(ComponentPlacement.grouped)
                    Text("As its own device").tag(ComponentPlacement.separate)
                }
            }
        }
        let volumes = store.snapshot.storage.filter { $0.deviceID == node.id }
        if !volumes.isEmpty {
            Section("Storage") { ForEach(volumes) { StorageUsageView(volume: $0, compact: false) } }
        }
        let network = store.networkLinks.filter { $0.deviceID == node.id && $0.isPhysicalPort && Date().timeIntervalSince($0.sampledAt) <= 5 }
        if !network.isEmpty {
            Section("Network") { ForEach(network) { link in row("Ethernet", link.label) } }
        }
        technicalDetails {
            if store.mapTitle(for: node) != node.name { row("System name", node.name) }
            if let vendor = node.vendorID { row("Vendor ID", String(format: "0x%04X", vendor)) }
            if let product = node.productID { row("Product ID", String(format: "0x%04X", product)) }
            if node.isUSB4Tunnel == true { row("Transport", "USB4 tunnel") }
            ForEach(Array(node.power.enumerated()), id: \.offset) { _, value in row(value.label, "\(value.milliamps) mA") }
            row("Path", store.snapshot.ancestry(of: node.id).map { store.mapTitle(for: $0) }.joined(separator: " › "))
            row("Registry path", node.registryPath)
        }
    }
    @ViewBuilder private func connectedTo(_ node: HardwareNode) -> some View {
        if let parent = store.snapshot.connectionParent(of: node.id) {
            LabeledContent("Connected through") {
                Button(store.mapTitle(for: parent)) { store.selection = .device(parent.id) }.buttonStyle(.link)
            }
        } else if let port = store.physicalPort(for: node), node.kind != .controller {
            LabeledContent("Plugged into") {
                Button(port.name) { store.selection = .socket(port.id) }.buttonStyle(.link)
            }
        }
    }
    private func nodeSummary(_ node: HardwareNode) -> String {
        switch node.kind {
        case .controller: return "USB host controller"
        case .port: return node.transport ?? "USB branch"
        case .hub, .device:
            let kind = node.transport?.replacingOccurrences(of: " router", with: "") ?? node.deviceDescription
            return node.speed.map { kind + " · " + $0.label } ?? kind
        }
    }

    // MARK: Display

    @ViewBuilder private func displaySections(_ display: DisplayDevice) -> some View {
        Section {
            if let signal = display.signal {
                row("Resolution", signal.resolution.label)
                if let range = signal.variableRefreshRange { row("Refresh rate", "Variable · " + range.label) }
                else { row("Refresh rate", String(format: "%g Hz", (signal.refreshRate * 100).rounded() / 100)) }
            } else if let rate = display.refreshRate {
                row("Refresh rate", String(format: "%g Hz", rate))
            }
            row("Looks like", "\(display.width) × \(display.height)")
                .help("The desktop size macOS presents; the display receives the resolution above.")
            if let node { connectedTo(node) }
        }
        technicalDetails {
            if let native = display.nativeResolution { row("Native resolution", native.label) }
            if let clock = display.signal?.pixelClockHz { row("Pixel clock", String(format: "%.2f MHz", clock / 1_000_000)) }
            if let capacity = display.linkCapacity {
                row("Link", "\(capacity.lanes) × " + String(format: "%g Gb/s", capacity.gigabitsPerLane) + " · " + capacity.payloadLabel + " usable")
            }
            if let edid = display.edid {
                row("Manufacturer code", edid.manufacturer)
                row("Product ID", String(format: "0x%04X", edid.product))
                if let serial = edid.serialText ?? (edid.serial == 0 ? nil : String(edid.serial)) { row("Serial number", serial) }
                row("Made in", String(edid.manufactureYear))
                row("EDID version", edid.version)
                Button("Copy EDID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(edid.hex, forType: .string)
                }
            }
            if !display.availableModes.isEmpty {
                InspectorDisclosure("Available modes (\(display.availableModes.count))") {
                    ForEach(display.availableModes) { mode in
                        Text(mode.label).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func isActive(_ socket: SocketConnection) -> Bool {
        !socket.devices.isEmpty || socket.connectors.contains { $0.connectionActive == true || !$0.links.isEmpty }
    }
    private func portName(for connectorID: String) -> String {
        store.physicalTopology.sockets.first { $0.connectors.contains { $0.id == connectorID } }?.port.name
            ?? store.snapshot.connectors.first { $0.id == connectorID }?.label ?? "Unknown port"
    }
    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
    /// Everything technical, collapsed by default, with no explanatory text.
    private func technicalDetails<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let rows = content()
        return Section {
            InspectorDisclosure("Technical Details") {
                rows.font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PowerGraph: View {
    let samples: [PowerSample]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let readings = samples.compactMap { sample -> (Date, Double)? in
                    sample.liveInput(at: sample.sampledAt).map { (sample.sampledAt, $0.value) }
                }
                guard let end = samples.last?.sampledAt else { return }
                let maximum = max(10, (readings.map { $0.1 }.max() ?? 10) * 1.15)
                var path = Path(), last: Date?
                for sample in samples {
                    guard let input = sample.liveInput(at: sample.sampledAt) else { last = nil; continue }
                    let date = sample.sampledAt, value = input.value
                    let point = CGPoint(x: size.width * (1 - end.timeIntervalSince(date) / 60), y: size.height * (1 - value / maximum))
                    if let previous = last, date.timeIntervalSince(previous) <= 3 { path.addLine(to: point) }
                    else { path.move(to: point) }
                    last = date
                }
                context.stroke(path, with: .color(.green), lineWidth: 2)
            }.background(.green.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            Text("Last 60 seconds · peak " + String(format: "%.1f W", samples.compactMap { $0.liveInput(at: $0.sampledAt)?.value }.max() ?? 0)).font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Mac input power over the last sixty seconds")
    }
}

/// An expandable inspector row. Detail text inside may be small, but the row title always
/// uses the standard body font so every row in the form lines up.
private struct InspectorDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        DisclosureGroup { content() } label: { Text(title).font(.body).foregroundStyle(.primary) }
    }
}
