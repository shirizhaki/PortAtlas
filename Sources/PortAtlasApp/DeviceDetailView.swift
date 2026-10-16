import SwiftUI
import PortAtlasCore

/// One inspector for the Mac, physical sockets, devices and individual routes.
struct DeviceDetailView: View {
    @EnvironmentObject private var store: AtlasStore
    private var node: HardwareNode? {
        switch store.selection {
        case .device(let id), .connection(let id): return store.snapshot.node(id)
        case .display(let id): return store.snapshot.nodes.first { $0.displayID == id }
        default: return nil
        }
    }
    private var socket: SocketConnection? {
        if case .socket(let id) = store.selection { return store.physicalTopology.sockets.first { $0.id == id } }
        if case .connector(let id) = store.selection { return store.physicalTopology.sockets.first { $0.connectors.contains { $0.id == id } } }
        if let node, let port = store.physicalPort(for: node) { return store.physicalTopology.sockets.first { $0.id == port.id } }
        return nil
    }
    private var connectors: [HardwareConnector] {
        if let socket { return socket.connectors }
        if case .connector(let id) = store.selection { return store.snapshot.connectors.filter { $0.id == id } }
        if let node, let path = store.snapshot.connectorPath(for: node.id) { return store.snapshot.connectors.filter { $0.id == path } }
        return []
    }
    private var display: DisplayDevice? {
        if case .display(let id) = store.selection { return store.displays.first { $0.id == id } }
        return node?.displayID.flatMap { id in store.displays.first { $0.id == id } }
    }
    private var title: String {
        if let node { return store.mapTitle(for: node) }
        return socket?.port.name ?? display?.name ?? connectors.first?.label ?? "This Mac"
    }
    private var isMac: Bool { store.selection == .mac }
    private var subtitle: String {
        if isMac { return store.snapshot.modelIdentifier }
        if display != nil { return "Display" }
        if let node {
            if node.kind == .controller { return "USB host controller" }
            return node.kind == .port ? (node.transport ?? "USB branch") : node.deviceDescription
        }
        return socket?.isMagSafe == true ? "Power port" : "Physical port"
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(title, systemImage: isMac ? (store.snapshot.formFactor == .laptop ? "laptopcomputer" : "desktopcomputer") : display != nil ? "display" : node?.symbol ?? "cable.connector")
                        .font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.selection = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }.help("Hide inspector · Escape").accessibilityLabel("Hide inspector")
            }.buttonStyle(.borderless).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isMac { macDetails }
                    else {
                        if node?.kind != .controller { group("Connection") {
                            if let socket {
                                if node?.kind == .device || node?.kind == .hub { fact("Physical port", socket.port.name) }
                                else { fact("Side", socket.port.side.label) }
                                if socket.devices.isEmpty && !socket.connectors.isEmpty && socket.connectors.allSatisfy({ $0.connectionActive == false }) {
                                    fact("Status", "Not connected")
                                } else if socket.connectors.isEmpty { fact("Status", socket.status)
                                } else { fact(node?.kind == .device || node?.kind == .hub ? "Upstream connection" : "Connection", store.connectionLabel(for: socket)) }
                            } else if node?.kind != .controller { fact("Physical port", "Unknown") }
                            if let node {
                                if node.displayID == nil && (node.kind == .device || node.kind == .hub) { fact("Connection speed", node.speed?.label ?? "Unavailable") }
                                if let parent = store.snapshot.connectionParent(of: node.id) {
                                    Button { store.selectedID = parent.id } label: { Label("Via " + store.mapTitle(for: parent), systemImage: parent.symbol) }.buttonStyle(.link)
                                }
                                if node.isUSB4Tunnel == true { fact("Transport", "USB4 tunnel") }
                            }
                            if node == nil, !connectors.isEmpty {
                                if socket == nil { fact("Status", connectors.contains { $0.connectionActive == true } ? "Connected" : connectors.allSatisfy { $0.connectionActive == false } ? "Not connected" : "Unavailable") }
                            }
                        } }
                        if let node, store.canPlaceComponent(node) { componentPlacement(node) }
                        if let display { displayDetails(display) }
                        if !connectors.isEmpty || socket != nil { connectorDetails }
                        if let node { deviceDetails(node) }
                    }
                }.padding(20)
            }
        }.background(MapContentBackground(inspector: true))
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 360)
    }
    @ViewBuilder private var macDetails: some View {
        group("Power") {
            fact("Status", store.powerSample.chargingLabel)
            if let percentage = store.powerSample.batteryPercent { fact("Battery", "\(percentage)%") }
            if let input = store.liveInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current power input").font(.caption).foregroundStyle(.secondary)
                    Text(input.label).font(.system(.title, design: .rounded).weight(.medium)).monospacedDigit().foregroundStyle(MapPowerStyle.incoming)
                }.accessibilityElement(children: .combine)
                PowerGraph(samples: store.powerHistory.samples).frame(height: 80)
                if let voltage = store.powerSample.inputVoltage, voltage.isFresh(at: Date()) { fact("Input voltage", voltage.label) }
                if let current = store.powerSample.inputCurrent, current.isFresh(at: Date()) { fact("Input current", current.label) }
            } else if store.powerStatus.externalPower == true { fact("Current power input", "Unavailable") }
            if let battery = store.powerSample.battery, battery.isFresh(at: Date()) {
                fact(battery.value < 0 ? "Battery discharge" : battery.value > 0 ? "Battery charging" : "Battery power", String(format: "%.1f W", abs(battery.value)))
            }
            if let watts = store.powerStatus.adapterWatts, store.powerStatus.externalPower == true { fact("Adapter rating", "\(watts) W") }
            if let name = store.powerSample.adapterName { fact("Adapter", name) }
            if let route = store.powerRoute, let connector = store.snapshot.connectors.first(where: { $0.id == route.connectorID }) {
                Button { store.selection = .connector(connector.id) } label: { Label("Input via " + connector.label + " (inferred)", systemImage: "bolt.fill") }.buttonStyle(.link)
            } else if store.powerStatus.externalPower == true { fact("Input port", "Unknown") }
            DisclosureGroup("Measurement details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Power input covers the whole Mac. Battery power is calculated separately from battery voltage and current.")
                    if store.liveInput?.source.hasPrefix("AppleSmartBattery") == true {
                        Text("Using battery-controller telemetry. These readings can update more slowly than the live SMC source.")
                    }
                    if let source = store.liveInput?.source { fact("Input source", source) }
                    if let route = store.powerRoute { Text(route.label) }
                    Text("The adapter rating and negotiated power limit describe available power, not current consumption.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }
        if let total = store.totalOutput { group("Power supplied") {
            fact("Total measured output", String(format: "%.1f W", total))
            Text("Sum of available Mac-port measurements; unreported ports are not included.").font(.caption).foregroundStyle(.secondary)
        } }
        if !store.displays.isEmpty { group("Displays") {
            ForEach(store.displays) { display in
                Button { store.selection = .display(display.id) } label: { Label(display.name, systemImage: "display") }.buttonStyle(.link)
                Text(store.displayLabel(display.id) ?? "").font(.caption).foregroundStyle(.secondary)
            }
        } }
    }
    private func componentPlacement(_ node: HardwareNode) -> some View {
        group("Physical placement") {
            Picker("Placement", selection: Binding(get: { store.presentation.placement(for: node) }, set: { store.setPlacement($0, for: node) })) {
                ForEach(ComponentPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.menu)
            Text("Applies to Physical view only. Logical view keeps the reported connections.").font(.caption).foregroundStyle(.secondary)
            if let error = store.componentLayoutError {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Reset saved component layout") { store.resetComponentLayout() }.buttonStyle(.link)
            }
        }
    }
    private func displayDetails(_ display: DisplayDevice) -> some View {
        group("Display") {
            fact("Signal", display.mapLabel)
            if let signal = display.signal {
                fact("Refresh mode", signal.variableRefreshRange != nil ? "Variable timing selected" : "Variable timing not reported")
                fact("Nominal refresh rate", String(format: "%g Hz", (signal.refreshRate * 100).rounded() / 100))
                if let range = signal.variableRefreshRange { fact("VRR range", range.label) }
            } else if let rate = display.refreshRate {
                fact("macOS mode rate", String(format: "%g Hz", rate))
            }
            fact("Instantaneous refresh rate", "Not reported")
            fact("Looks like", "\(display.width) × \(display.height)")
            if let native = display.nativeResolution { fact("Native resolution", native.label) }
            if let rendered = display.renderedResolution, rendered != display.signal?.resolution {
                fact("Rendered desktop", rendered.label)
            }
            if let clock = display.signal?.pixelClockHz { fact("Pixel clock", String(format: "%.2f MHz", clock / 1_000_000)) }
            if let capacity = display.linkCapacity {
                fact("Display link capacity", capacity.payloadLabel + " payload")
                fact("Raw link rate", capacity.rawLabel)
                fact("Link lanes", "\(capacity.lanes) × " + String(format: "%g Gb/s", capacity.gigabitsPerLane))
            }
            if node?.transport?.contains("tunnel") == true { fact("Reserved Thunderbolt bandwidth", "Unavailable") }
            DisclosureGroup("Available modes (\(display.availableModes.count))") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Desktop modes currently offered by macOS for this connection. Scaled render sizes can differ from the signal sent to the display.")
                        .font(.caption).foregroundStyle(.secondary)
                    if display.availableModes.isEmpty { Text("Modes unavailable").font(.caption).foregroundStyle(.secondary) }
                    ForEach(display.availableModes) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label).font(.caption.monospacedDigit())
                            if let render = mode.renderLabel { Text(render).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }.padding(.top, 8)
            }.font(.caption)
            DisclosureGroup("Display capabilities · EDID") {
                VStack(alignment: .leading, spacing: 12) {
                    if let edid = display.edid {
                        if let name = edid.name { fact("Display name", name) }
                        fact("Manufacturer", edid.manufacturer)
                        fact("Product ID", String(format: "0x%04X", edid.product))
                        fact("Serial number", edid.serialText ?? (edid.serial == 0 ? "Not provided" : String(edid.serial)))
                        fact("EDID version", edid.version)
                        fact("Manufacture year", String(edid.manufactureYear))
                        fact("EDID size", "\(edid.data.count) bytes · checksums verified")
                        if !edid.detailedTimings.isEmpty {
                            Text("Advertised detailed timings").font(.caption.weight(.semibold))
                            ForEach(Array(edid.detailedTimings.enumerated()), id: \.offset) { _, timing in
                                Text(timing.label).font(.caption.monospacedDigit())
                            }
                        }
                        Text("Detailed timings decoded from EDID. Additional standard and extension video modes may be advertised; this list is not exhaustive. EDID describes the display, not the Mac port’s maximum capability.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Copy raw EDID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(edid.hex, forType: .string)
                        }.buttonStyle(.link)
                    } else {
                        Text("A unique, validated EDID is unavailable for this display.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }.font(.caption)
            DisclosureGroup("About these readings") {
                Text("Signal timing comes from the active display controller. A VRR range describes the selected variable timing. Nominal refresh rate is not a live measurement of HDMI refresh or application FPS. Missing VRR fields mean variable timing is not reported. Desktop scaling and render size can differ from the signal sent to the display.")
                Text("Display link capacity describes the negotiated link. Video usage and reserved Thunderbolt bandwidth require additional hardware readings, including color format and compression.")
            }.font(.caption).foregroundStyle(.secondary)
            fact("Route", node != nil ? "Matched by display identity" : "Unknown")
        }
    }
    private var connectorDetails: some View {
        group(node?.kind == .device || node?.kind == .hub ? "Upstream port" : "Port") {
            if let socket, socket.devices.isEmpty && !socket.connectors.contains(where: { $0.connectionActive == true }) {
                fact("Port support", socket.isMagSafe ? "MagSafe" : store.capabilityLabel(for: socket.port))
            }
            ForEach(connectors) { connector in
                if let output = store.output(for: connector.id) {
                    Label("Power out · supplied by Mac", systemImage: "arrow.up").font(.callout).foregroundStyle(MapPowerStyle.outgoing)
                    fact("Current output", output.label)
                    fact("Output voltage", String(format: "%.2f V", output.volts))
                    fact("Output current", String(format: "%.2f A", output.amps))
                    if let limit = output.configuredWatts { fact("Configured output limit", String(format: "%g W", limit)) }
                    Text("Measured at the Mac port; this does not establish downstream device charging or a USB-PD contract.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Output reading source") { Text(output.source).font(.caption).foregroundStyle(.secondary) }
                }
                if let contract = connector.powerContractWatts, connector.connectionActive != false {
                    fact("Negotiated power limit", "\(contract) W")
                    if let mv = connector.power?.voltageMillivolts { fact("Negotiated voltage", String(format: "%.1f V", Double(mv) / 1000)) }
                    if let ma = connector.power?.currentMilliamps { fact("Negotiated current limit", String(format: "%.2f A", Double(ma) / 1000)) }
                }
                if let cable = connector.cable, connector.connectionActive == true {
                    fact("Cable", cable.productType)
                    if let revision = cable.pdRevision { fact("Cable PD revision", String(revision)) }
                }
                if connector.id == store.powerRoute?.connectorID {
                    Label("Power in (inferred)", systemImage: "arrow.down").font(.callout).foregroundStyle(MapPowerStyle.incoming)
                }
                ForEach(connector.links) { link in
                    fact(link.label, link.detail ?? "Active")
                }
            }
            if connectors.contains(where: { $0.id == store.powerRoute?.connectorID }) {
                Button("Show current power input") { store.selection = .mac }.buttonStyle(.link)
            }
            DisclosureGroup("Port details") {
                VStack(alignment: .leading, spacing: 12) {
                    if let socket {
                        fact("Port support", socket.isMagSafe ? "MagSafe" : store.capabilityLabel(for: socket.port))
                        fact("Position source", socket.isMagSafe ? "Detected MagSafe" : socket.isHDMI && !socket.hasSavedAssignment ? "Automatic HDMI position · adjustable in Settings" : "Port settings")
                        if !socket.isMagSafe { fact("Support source", store.capabilitySource(for: socket.port)) }
                    }
                    ForEach(connectors) { connector in
                        if let watts = connector.power?.advertisedWatts, connector.connectionActive != false { fact("Advertised power limit", "\(watts) W") }
                        if !connector.laneDetails.isEmpty { fact("Reported PHY allocation", connector.laneDetails.joined(separator: "\n")) }
                    }
                    if let route = store.powerRoute, connectors.contains(where: { $0.id == route.connectorID }) { Text(route.label).font(.caption).foregroundStyle(.secondary) }
                    Text("Connection speed describes the link, not measured data transfer. Power limits describe available power, not consumption.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.font(.caption)
        }
    }
    @ViewBuilder private func deviceDetails(_ node: HardwareNode) -> some View {
        let volumes = store.snapshot.storage.filter { $0.deviceID == node.id }
        if !volumes.isEmpty {
            group("Storage") {
                ForEach(volumes) { StorageUsageView(volume: $0, compact: false) }
                Text("Updated when connections refresh. APFS volumes may share capacity.").font(.caption).foregroundStyle(.secondary)
            }
        }
        let network = store.networkLinks.filter { $0.deviceID == node.id && Date().timeIntervalSince($0.sampledAt) <= 5 }
        if !network.isEmpty {
            group("Network") {
                ForEach(network) { link in fact("Ethernet speed", link.label) }
                Text("Network link speed is independent of the USB connection rate.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if !node.power.isEmpty {
            group("Accessory power") {
                ForEach(Array(node.power.enumerated()), id: \.offset) { _, value in fact(value.label, "\(value.milliamps) mA") }
                Text("Reported allocation/supply; actual accessory consumption is unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                if let manufacturer = node.manufacturer { fact("Manufacturer", manufacturer) }
                if store.mapTitle(for: node) != node.name { fact("System name", node.name) }
                if let vendor = node.vendorID { fact("Vendor ID", String(format: "0x%04X", vendor)) }
                if let product = node.productID { fact("Product ID", String(format: "0x%04X", product)) }
                if let speed = node.speed { fact("Speed source", speed.source) }
                if node.interfaceClasses?.contains(8) == true { fact("Live throughput", "Not measured") }
                group("Reported path") {
                    ForEach(store.snapshot.ancestry(of: node.id)) { ancestor in
                        Button { store.selectedID = ancestor.id } label: { Label(ancestor.name, systemImage: ancestor.symbol) }.buttonStyle(.link)
                    }
                }
                Text(node.registryPath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                if store.attachmentHistory.laterAttachments.contains(node.id) { Text("Observed joining an established hub this session; enclosure membership is unknown.").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 12)
        }.font(.caption)
    }
    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .trailing)
        }.font(.callout).fixedSize(horizontal: false, vertical: true)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
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
