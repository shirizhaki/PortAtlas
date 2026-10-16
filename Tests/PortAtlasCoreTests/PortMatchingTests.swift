import Foundation
import Testing
import PortAtlasCore

struct PortMatchingTests {
    private let a = HardwareConnector(id: "fixture://a", number: 1, kind: .usbA)
    private let c = HardwareConnector(id: "fixture://c", number: 1)
    private func snapshot(aConnected: Bool = true, cConnected: Bool = false, extra: [HardwareNode] = []) -> TopologySnapshot {
        var nodes: [HardwareNode] = []
        if aConnected { nodes.append(HardwareNode(id: "dock", name: "Fixture dock", kind: .hub, registryPath: "fixture://dock", connectorPath: a.id)) }
        if cConnected { nodes.append(HardwareNode(id: "ssd", name: "Fixture SSD", kind: .device, connectorPath: c.id)) }
        return TopologySnapshot(nodes: nodes + extra, modelIdentifier: "FutureMac", connectors: [a,c])
    }
    @Test func suggestionsRequireOneChangedHostConnection() {
        let empty = PortMatchingObservation(snapshot: snapshot(aConnected: false))
        let dock = PortMatchingObservation(snapshot: snapshot())
        let both = PortMatchingObservation(snapshot: snapshot(cConnected: true))
        #expect(dock.suggestedConnector(since: empty) == a.id)
        #expect(both.suggestedConnector(since: empty) == nil)
        #expect(both.suggestedConnector(since: dock) == c.id)
        #expect(dock.suggestedConnector(since: both) == nil)
        let child = HardwareNode(id: "receiver", name: "Receiver", kind: .device, parentID: "dock")
        #expect(PortMatchingObservation(snapshot: snapshot(extra: [child])).suggestedConnector(since: dock) == nil)
        #expect(dock.onlyOccupiedConnector == a.id)
        #expect(both.onlyOccupiedConnector == nil)
    }
    @Test func matchingIsModelIndependentAndReusesPosition() throws {
        let tree = snapshot()
        var config = PortConfiguration()
        let matched = config.match(a, snapshot: tree, side: .back, name: "Rear USB-A")
        let id = try #require(matched)
        #expect(config.match(a, snapshot: tree, side: .front, name: "Front USB-A") == id)
        #expect(config.ports.count == 1)
        #expect(config.assignments.count == 1)
        #expect(config.ports[0].side == .front)
        let roundtrip = try JSONDecoder().decode(PortConfiguration.self, from: JSONEncoder().encode(config))
        let view = PhysicalTopology(snapshot: tree, configuration: roundtrip)
        #expect(view.sockets.first?.isUSBA == true)
        #expect(view.sockets.first?.devices.map(\.id) == ["dock"])
        #expect(a.label == "USB-A socket 1")
    }
    @Test func existingEmptySlotCanBeReusedButOccupiedSlotCannotBeOverwritten() throws {
        let tree = snapshot(cConnected: true)
        var config = PortConfiguration()
        let empty = PhysicalPort(name: "Back 1", side: .back)
        config.ports = [empty]
        #expect(config.match(a, snapshot: tree, side: .back, name: "Back 1", replacing: empty.id) == empty.id)
        let before = config
        #expect(config.match(c, snapshot: tree, side: .back, name: "Conflict", replacing: empty.id) == nil)
        #expect(config == before)
        #expect(config.match(a, snapshot: tree, side: .left, name: "   ") == nil)
        let missing = HardwareConnector(id: "missing")
        #expect(config.match(missing, snapshot: tree, side: .left, name: "Missing") == nil)
    }
    @Test func companionBranchesStayOneUSBASocket() throws {
        let tree = TopologySnapshot(nodes: [
            HardwareNode(id: "usb2", name: "USB2", kind: .port, registryPath: "fixture://usb2", connectorPath: a.id),
            HardwareNode(id: "usb3", name: "USB3", kind: .port, registryPath: "fixture://usb3", connectorPath: a.id),
            HardwareNode(id: "mouse", name: "Mouse", kind: .device, parentID: "usb2"),
            HardwareNode(id: "drive", name: "Drive", kind: .device, parentID: "usb3")
        ], modelIdentifier: "Fixture", connectors: [a])
        var config = PortConfiguration()
        #expect(config.match(a, snapshot: tree, side: .back, name: "USB-A") != nil)
        let view = PhysicalTopology(snapshot: tree, configuration: config)
        #expect(view.sockets.count == 1)
        #expect(Set(view.sockets[0].devices.map(\.id)) == ["mouse", "drive"])
        #expect(view.unplaced.isEmpty)
    }
    @Test func USBARequiresBuiltInEvidenceAndCannotBecomeAnInput() {
        #expect(ConnectorKind.detected(portType: "USB-A", builtIn: true, appleSilicon: true) == .usbA)
        #expect(ConnectorKind.detected(portType: "USB-A", builtIn: false, appleSilicon: true) == nil)
        #expect(ConnectorKind.detected(portType: "USB-A", builtIn: nil, appleSilicon: true) == nil)
        #expect(ConnectorKind.detected(portType: "SD Card", builtIn: true, appleSilicon: true) == nil)
        let malformed = HardwareConnector(id: "a", connectionActive: true, powerContractWatts: 60, kind: .usbA)
        #expect(PowerRouting.resolve(connectors: [malformed], externalPower: true) == nil)
    }
}
