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
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Match physical ports").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Use one recognizable USB device and move it between sockets. Confirm each position; the app remembers the connector for other devices too.")
                .foregroundStyle(.secondary)
            if let saved { Label(saved, systemImage: "checkmark.circle").foregroundStyle(.green) }
            VStack(alignment: .leading, spacing: 12) {
                Text("1. Connect a device").font(.headline)
                Text("Connect directly to the Mac, then confirm the suggested connection.").font(.callout).foregroundStyle(.secondary)
                Picker("Connected device", selection: $selected) {
                    Text("Choose a connection").tag(Optional<String>.none)
                    ForEach(connected) { connector in
                        Text(connectionLabel(connector)).tag(Optional(connector.id))
                    }
                }
                if connected.isEmpty {
                    Text("Waiting for a USB device. A charging cable alone cannot identify a USB connection.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Refresh connections", systemImage: "arrow.clockwise") { store.refresh() }.disabled(store.isRefreshing)
            }.padding(16).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                Text("2. Confirm its position").font(.headline)
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
                Text(store.snapshot.formFactor == .laptop
                     ? "Add sockets from the screen toward the front on each side. Fine-tune their order in Settings."
                     : "Add front and back sockets from left to right, looking directly at that panel. Fine-tune their order in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).disabled(selected == nil)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Confirm USB side and order here. MagSafe and a single built-in HDMI port appear automatically when reported.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Save position") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || side == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.settingsNeedReset)
            }
        }.padding(24).frame(width: 580).fixedSize(horizontal: false, vertical: true)
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
