import SwiftUI
import PortAtlasCore

struct PortMatchingView: View {
    @EnvironmentObject private var store: AtlasStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selected: String?
    @ViewState private var side: PortSide?
    @ViewState private var name = ""
    @ViewState private var target: UUID?
    @ViewState private var automaticName = true
    @ViewState private var previous: PortMatchingObservation?
    @ViewState private var saved: String?
    @ViewState private var error: String?
    private var observation: PortMatchingObservation { PortMatchingObservation(snapshot: store.liveSnapshot) }
    private var connected: [HardwareConnector] {
        store.liveSnapshot.connectors.filter { !(observation.roots[$0.id] ?? []).isEmpty }
    }
    private var emptySlots: [SocketConnection] {
        store.physicalTopology.sockets.filter { $0.connectors.isEmpty && !$0.hasSavedAssignment }
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("Match Physical Ports").font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            Form {
                Section {
                    Text("Plug one USB device into each port in turn and save where it is. PortAtlas remembers every port.")
                        .foregroundStyle(.secondary)
                    if let saved { Label(saved, systemImage: "checkmark.circle.fill").foregroundStyle(MapPowerStyle.incoming) }
                }
                Section {
                    Picker("Connected device", selection: $selected) {
                        Text("Choose a connection").tag(Optional<String>.none)
                        ForEach(connected) { connector in
                            Text(connectionLabel(connector)).tag(Optional(connector.id))
                        }
                    }
                    LabeledContent {
                        Button("Refresh") { store.refresh() }.disabled(store.isRefreshing)
                    } label: {
                        if connected.isEmpty {
                            Text("Waiting for a USB device")
                            Text("A charger alone can't identify a port.")
                        } else {
                            Text("Don't see your device?")
                        }
                    }
                } header: {
                    Text("1. Connect a device")
                } footer: {
                    FormFooter("Plug the device straight into the Mac, not into a hub or dock.")
                }
                Section {
                    Picker("Side", selection: $side) {
                        Text("Choose a side").tag(Optional<PortSide>.none)
                        ForEach(PortSide.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    TextField("Port name", text: Binding(get: { name }, set: { value in
                        if name != value { name = value; automaticName = value.isEmpty }
                    }))
                    if !emptySlots.isEmpty {
                        Picker("Save to", selection: $target) {
                            Text("New or existing position for this connection").tag(Optional<UUID>.none)
                            ForEach(emptySlots) { Text($0.port.name).tag(Optional($0.id)) }
                        }
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                } header: {
                    Text("2. Confirm its position")
                } footer: {
                    FormFooter(store.snapshot.formFactor == .laptop
                         ? "Name side ports in order from the screen toward you. MagSafe and HDMI are found automatically."
                         : "Name ports left to right as you face each panel. HDMI is found automatically.")
                }.disabled(selected == nil)
            }.formStyle(.grouped)
            Divider()
            // Standard sheet button row: dismiss on the left of the default action.
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Position") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || side == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.settingsNeedReset)
            }.padding(16)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            previous = observation
            selected = observation.onlyOccupiedConnector
            prepareSelection()
        }
        .onChange(of: observation) { _, current in
            if let old = previous, let suggestion = current.suggestedConnector(since: old) {
                selected = suggestion; saved = nil
            }
            if let selected, !connected.contains(where: { $0.id == selected }) { self.selected = nil }
            previous = current
        }
        .onChange(of: selected) { _, _ in prepareSelection() }
        .onChange(of: side) { _, _ in
            if automaticName { name = defaultName }
        }
        .onChange(of: target) { _, id in
            if let port = emptySlots.first(where: { $0.id == id })?.port { automaticName = false; side = port.side; name = port.name }
        }
    }
    private var defaultName: String {
        guard let side else { return "" }
        return "\(side.label) \(store.configuration.ports(on: side).count + 1)"
    }
    private func prepareSelection() {
        target = nil; error = nil
        if let socket = store.physicalTopology.sockets.first(where: { socket in socket.connectors.contains { $0.id == selected } }) {
            automaticName = false; side = socket.port.side; name = socket.port.name
        } else { automaticName = true; side = nil; name = "" }
    }
    private func connectionLabel(_ connector: HardwareConnector) -> String {
        let names = store.liveSnapshot.accessoryRoots.filter { store.liveSnapshot.connectorPath(for: $0.id) == connector.id }.map(\.name)
        return names.prefix(2).joined(separator: ", ") + " · " + connector.label
    }
    private func save() {
        guard let selected, let side, connected.contains(where: { $0.id == selected }) else { return }
        guard store.saveMatchedPort(connectorID: selected, side: side, name: name, replacing: target) else {
            error = store.settingsError ?? "The connection or position changed. Check the selection and try again."
            return
        }
        saved = "Saved \(name). Move the device to the next socket, or choose another connection."
        self.selected = nil; target = nil; previous = observation
    }
}
