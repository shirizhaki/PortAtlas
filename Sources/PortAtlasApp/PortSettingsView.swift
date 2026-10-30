import SwiftUI
import PortAtlasCore

struct PortSettingsView: View {
    @EnvironmentObject private var store: AtlasStore
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .system
    @ViewState private var showingPortMatcher = false
    @ViewState private var confirmReset = false
    @Environment(\.undoManager) private var undoManager
    private let sides: [PortSide] = [.left, .right, .front, .back]
    private var projection: PhysicalTopology { store.physicalTopology }
    var body: some View {
        // A grouped form matches System Settings: sectioned rows, standard controls, no custom panels.
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                LabeledContent {
                    Button("Match Ports…") { showingPortMatcher = true }
                } label: {
                    Text("Physical positions")
                    Text("Plug a device into each port to name where it is.")
                }
                ForEach(projection.sockets.filter { $0.isHDMI && !$0.hasSavedAssignment }) { socket in
                    LabeledContent {
                        Button("Adjust Position") {
                            let port = socket.port
                            store.configuration.ports.append(port)
                            if let connector = socket.connectors.first {
                                store.configuration.assignConnector(connector, snapshot: store.liveSnapshot, to: port.id)
                            }
                        }.disabled(store.settingsNeedReset)
                    } label: {
                        Text("Built-in HDMI")
                        Text("Detected automatically · \(socket.port.side.label) side")
                    }
                }
                if let error = store.settingsError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    if store.settingsNeedReset { Button("Reset Saved Settings…") { confirmReset = true } }
                }
            } header: {
                Text("Port Layout")
            } footer: {
                FormFooter(store.snapshot.formFactor == .desktop
                     ? "Ports are listed left to right as you face each panel."
                     : "Side ports are listed from the screen toward you.")
            }
            ForEach(sides) { side in
                let ports = store.configuration.ports(on: side)
                Section {
                    if ports.isEmpty { Text("No ports on this side").foregroundStyle(.secondary) }
                    ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                        portRow(port, index: index, count: ports.count)
                    }
                } header: {
                    HStack {
                        Text(side.label)
                        Spacer()
                        Button("Add Port", systemImage: "plus") {
                            store.configuration.ports.append(PhysicalPort(name: "\(side.label) \(ports.count + 1)", side: side))
                        }.buttonStyle(.borderless).labelStyle(.iconOnly).help("Add a port on the \(side.label.lowercased()) side")
                    }
                }
            }
            Section {
                DisclosureGroup("Connector details") {
                    if let profile = MacCapabilityProfile.verified(for: store.snapshot.modelIdentifier) {
                        Link("Apple model specifications", destination: profile.sourceURL)
                    }
                    ForEach(store.liveSnapshot.connectors.filter { $0.kind != .magSafe }) { connector in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choiceLabel(connector)).font(.callout.weight(.medium))
                            Text(connector.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            ForEach(store.liveSnapshot.nodes.filter { $0.kind == .port && $0.connectorPath == connector.id }) { node in
                                Text(node.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
        // Opening Settings must not put a port name into editing with its text selected.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .sheet(isPresented: $showingPortMatcher) { PortMatchingView().environmentObject(store) }
        .onChange(of: store.configuration) { _, _ in store.scheduleSave() }
        .onDisappear { store.flushPendingSave() }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 18)
                TextField("Port name", text: binding(port.id, \.name, fallback: port.name)).labelsHidden()
                Button { store.configuration.movePort(port.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).help("Move port earlier").accessibilityLabel("Move \(port.name) earlier")
                Button { store.configuration.movePort(port.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == count - 1).help("Move port later").accessibilityLabel("Move \(port.name) later")
                Button {
                    var next = store.configuration; next.removePort(port.id)
                    store.applyConfiguration(next, actionName: "Remove Port", undoManager: undoManager)
                } label: { Image(systemName: "trash") }
                    .help("Remove port · ⌘Z to undo").accessibilityLabel("Remove \(port.name)")
            }.buttonStyle(.borderless)
            Picker("Side", selection: binding(port.id, \.side, fallback: port.side)) {
                ForEach(sides) { Text($0.label).tag($0) }
            }
            Picker("Connection", selection: connectorBinding(port.id)) {
                Text("Unassigned").tag(Optional<String>.none)
                ForEach(store.liveSnapshot.connectors.filter { $0.kind != .magSafe }) { Text(choiceLabel($0)).tag(Optional($0.id)) }
            }.disabled(store.settingsNeedReset)
            if projection.sockets.first(where: { $0.id == port.id })?.isHDMI != true {
                Picker("Port support", selection: binding(port.id, \.capability, fallback: port.capability)) {
                    Text("Automatic · \(store.capabilityLabel(for: PhysicalPort(id: port.id, name: port.name, side: port.side)))").tag(Optional<PortCapability>.none)
                    ForEach(PortCapability.allCases) { Text($0.label).tag(Optional($0)) }
                }
            } else {
                LabeledContent("Port support", value: store.capabilityLabel(for: port))
            }
        }.padding(.vertical, 4)
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

/// Section footers in the System Settings style: small, secondary and leading-aligned.
struct FormFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}
