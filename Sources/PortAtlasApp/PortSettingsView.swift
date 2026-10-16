import SwiftUI
import PortAtlasCore

struct PortSettingsView: View {
    @EnvironmentObject private var store: AtlasStore
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .system
    @ViewState private var showingPortMatcher = false
    @ViewState private var confirmReset = false
    private let sides: [PortSide] = [.left, .right, .front, .back]
    private var projection: PhysicalTopology { store.physicalTopology }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Appearance").font(.headline)
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 200)
                }.padding(18).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Port Layout").font(.title2.weight(.semibold))
                    Text("Match a known USB device to its physical position, then use the arrows to set port order.").foregroundStyle(.secondary)
                    Button("Match ports…", systemImage: "cable.connector") { showingPortMatcher = true }
                    Text(store.snapshot.formFactor == .desktop
                         ? "Front and Back: the first port is the leftmost, looking directly at that panel. Left and Right: the first port is closest to the back."
                         : "Left and Right: the first port is closest to the screen. Front and Back: the first port is the leftmost, looking directly at that edge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.settingsError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    if store.settingsNeedReset { Button("Reset saved settings…") { confirmReset = true } }
                }
                ForEach(projection.sockets.filter { $0.isHDMI && !$0.hasSavedAssignment }) { socket in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Built-in HDMI").font(.headline)
                            Text("Detected automatically · \(socket.port.side.label) side").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Adjust position") {
                            let port = socket.port
                            store.configuration.ports.append(port)
                            if let connector = socket.connectors.first {
                                store.configuration.assignConnector(connector, snapshot: store.liveSnapshot, to: port.id)
                            }
                        }.disabled(store.settingsNeedReset)
                    }.padding(18).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                }
                ForEach(sides) { side in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(side.label).font(.title3.weight(.semibold))
                            Spacer()
                            Button("Add port", systemImage: "plus") {
                                store.configuration.ports.append(PhysicalPort(name: "\(side.label) \(store.configuration.ports(on: side).count + 1)", side: side))
                            }.buttonStyle(.borderless)
                        }
                        let ports = store.configuration.ports(on: side)
                        if ports.isEmpty { Text("No ports on this side").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 8) }
                        ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                            portRow(port, index: index, count: ports.count)
                        }
                    }.padding(18).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Port support is detected from hardware. Connection speed describes the attached device.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let profile = MacCapabilityProfile.verified(for: store.snapshot.modelIdentifier) {
                            Link("Apple model specifications", destination: profile.sourceURL).font(.caption)
                        }
                        ForEach(store.liveSnapshot.connectors.filter { $0.kind != .magSafe }) { connector in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(choiceLabel(connector)).font(.caption.weight(.medium))
                                Text(connector.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                ForEach(store.liveSnapshot.nodes.filter { $0.kind == .port && $0.connectorPath == connector.id }) { node in
                                    Text(node.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.top, 12)
                }.font(.caption)
            }.padding(30)
        }
        .sheet(isPresented: $showingPortMatcher) { PortMatchingView().environmentObject(store) }
        .onChange(of: store.configuration) { _, _ in store.saveSettings() }
        .alert("Reset port settings?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.resetSettings() }
        } message: { Text("This replaces saved socket names and assignments with empty settings.") }
    }
    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<PhysicalPort, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { store.configuration.ports.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
                set: { value in
                    if let index = store.configuration.ports.firstIndex(where: { $0.id == id }) {
                        store.configuration.ports[index][keyPath: keyPath] = value
                    }
                })
    }
    private func portRow(_ port: PhysicalPort, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                TextField("Port name", text: binding(port.id, \.name, fallback: port.name)).textFieldStyle(.plain).font(.headline)
                Spacer()
                Button { store.configuration.movePort(port.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).help("Move port earlier")
                Button { store.configuration.movePort(port.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == count - 1).help("Move port later")
                Button { store.configuration.removePort(port.id) } label: { Image(systemName: "trash") }
                    .foregroundStyle(.secondary).help("Remove port")
            }.buttonStyle(.borderless)
            HStack {
                Picker("Side", selection: binding(port.id, \.side, fallback: port.side)) {
                    ForEach(sides) { Text($0.label).tag($0) }
                }
                Text(store.capabilityLabel(for: port)).font(.caption).foregroundStyle(.secondary)
            }
            if projection.sockets.first(where: { $0.id == port.id })?.isHDMI != true {
            DisclosureGroup("Override port support") {
                Picker("Port support", selection: binding(port.id, \.capability, fallback: port.capability)) {
                    Text("Automatic · \(store.capabilityLabel(for: PhysicalPort(id: port.id, name: port.name, side: port.side)))").tag(Optional<PortCapability>.none)
                    ForEach(PortCapability.allCases) { Text($0.label).tag(Optional($0)) }
                }.padding(.top, 8)
            }.font(.caption)
            }
            Picker("Connection", selection: connectorBinding(port.id)) {
                Text("Unassigned").tag(Optional<String>.none)
                ForEach(store.liveSnapshot.connectors.filter { $0.kind != .magSafe }) { Text(choiceLabel($0)).tag(Optional($0.id)) }
            }.disabled(store.settingsNeedReset)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private func choiceLabel(_ connector: HardwareConnector) -> String {
        let names = store.liveSnapshot.accessoryRoots.filter {
            store.liveSnapshot.connectorPath(for: $0.id) == connector.id
        }.map(\.name)
        return "\(names.isEmpty ? "No device identified" : names.prefix(2).joined(separator: ", ")) · \(connector.label)"
    }
    private func connectorBinding(_ id: UUID) -> Binding<String?> {
        Binding(get: { projection.sockets.first { $0.id == id }?.connectors.first?.id },
                set: { store.matchConnector($0, to: id) })
    }
}
