import Foundation
import Testing
@testable import PortAtlasCore

struct PhysicalTopologyTests {
    private let connector = HardwareConnector(id: "fixture://socket-a", number: 1, connectionActive: true)
    private let port = PhysicalPort(name: "Left · near", side: .left)
    private var snapshot: TopologySnapshot {
        TopologySnapshot(nodes: [
            HardwareNode(id: "controller", name: "Controller", kind: .controller),
            HardwareNode(id: "usb2", name: "USB 2 branch", kind: .port, parentID: "controller",
                         registryPath: "fixture://usb2", connectorPath: connector.id),
            HardwareNode(id: "usb3", name: "USB 3 branch", kind: .port, parentID: "controller",
                         registryPath: "fixture://usb3", connectorPath: connector.id),
            HardwareNode(id: "storage", name: "Storage", kind: .device, parentID: "usb3")
        ], modelIdentifier: "FixtureMac", connectors: [connector])
    }
    @Test func thunderboltDockJoinsUSBAndPCIeWithoutDuplicatingRoots() {
        let tree = TopologySnapshot(nodes: [
            HardwareNode(id: "dock", name: "Dock", kind: .hub, connectorPath: connector.id, transport: "Thunderbolt / USB4 router"),
            HardwareNode(id: "controller", name: "USB controller", kind: .controller, parentID: "dock"),
            HardwareNode(id: "port", name: "Logical port", kind: .port, parentID: "controller"),
            HardwareNode(id: "hub", name: "USB hub", kind: .hub, parentID: "port"),
            HardwareNode(id: "usbSSD", name: "USB SSD", kind: .device, parentID: "hub", interfaceClasses: [8]),
            HardwareNode(id: "enclosure", name: "Enclosure", kind: .hub, parentID: "dock", transport: "Thunderbolt / USB4 router"),
            HardwareNode(id: "nvme", name: "SSD", kind: .device, parentID: "enclosure", interfaceClasses: [8], transport: "PCIe / NVMe storage")
        ], modelIdentifier: "FixtureMac", connectors: [connector])
        var config = PortConfiguration(); config.ports = [port]
        config.assignConnector(connector, snapshot: tree, to: port.id)
        let view = PhysicalTopology(snapshot: tree, configuration: config)
        #expect(view.unplaced.isEmpty)
        #expect(view.sockets[0].devices.map(\.id) == ["dock"])
        #expect(tree.connectedAccessoryCount == 1)
        #expect(Set(tree.connectionChildren(of: "dock").map(\.id)) == ["hub", "enclosure"])
        #expect(tree.children(of: "dock").contains { $0.id == "controller" })
        #expect(tree.connectorPath(for: "nvme") == connector.id)
        #expect(tree.connectorPath(for: "usbSSD") == connector.id)
        #expect(tree.node("nvme")?.deviceDescription == "PCIe / NVMe storage")
    }
    @Test func conflictingRouteEvidenceDoesNotChooseAConnector() {
        let tree = TopologySnapshot(nodes: [
            HardwareNode(id: "dock", name: "Dock", kind: .hub, connectorPath: "a"),
            HardwareNode(id: "port", name: "Port", kind: .port, parentID: "dock", connectorPath: "b"),
            HardwareNode(id: "ssd", name: "SSD", kind: .device, parentID: "port")
        ], modelIdentifier: "FixtureMac")
        #expect(tree.connectorPath(for: "ssd") == nil)
    }
    @Test func companionBranchesBecomeOnePhysicalSocket() {
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        let view = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(view.sockets.count == 1)
        #expect(view.sockets[0].devices.map(\.id) == ["storage"])
        #expect(view.sockets[0].connectors.count == 1)
        #expect(view.unplaced.isEmpty)
        #expect(configuration.physicalPort(for: snapshot.node("usb2")!, model: "FixtureMac") == port)
        #expect(configuration.physicalPort(for: snapshot.node("usb3")!, model: "FixtureMac") == port)
    }
    @Test func actualHubIsPreservedAndItsChildIsNotPromoted() {
        let hub = HardwareNode(id: "hub", name: "Hub", kind: .hub, parentID: "usb2")
        let child = HardwareNode(id: "keyboard", name: "Keyboard", kind: .device, parentID: "hub")
        let tree = TopologySnapshot(nodes: snapshot.nodes + [hub, child], modelIdentifier: "FixtureMac", connectors: [connector])
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: tree, to: port.id)
        let view = PhysicalTopology(snapshot: tree, configuration: configuration)
        #expect(Set(view.sockets[0].devices.map(\.id)) == ["storage", "hub"])
        #expect(tree.children(of: "hub").map(\.id) == ["keyboard"])
    }
    @Test func dualProtocolHubCountsAsOneExternalAccessoryWithoutChangingAncestry() {
        let nodes = snapshot.nodes.filter { $0.id != "storage" } + [
            HardwareNode(id: "hub2", name: "USB 2 hub", kind: .hub, parentID: "usb2"),
            HardwareNode(id: "hub3", name: "USB 3 hub", kind: .hub, parentID: "usb3"),
            HardwareNode(id: "ssd", name: "SSD", kind: .device, parentID: "hub3")
        ]
        let tree = TopologySnapshot(nodes: nodes, modelIdentifier: "FixtureMac", connectors: [connector])
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: tree, to: port.id)
        let view = PhysicalTopology(snapshot: tree, configuration: configuration)
        #expect(tree.connectedAccessoryCount == 1)
        #expect(view.sockets[0].status == "Connected")
        #expect(Set(view.sockets[0].devices.map(\.id)) == ["hub2", "hub3"])
        #expect(tree.node("hub2")?.parentID == "usb2")
        #expect(tree.node("hub3")?.parentID == "usb3")
        #expect(tree.node("ssd")?.parentID == "hub3")
    }
    @Test func noPositionIsGuessedFromOnlyRemainingSocket() {
        var configuration = PortConfiguration(); configuration.ports = [port]
        let view = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(view.sockets[0].status == "Position not matched")
        #expect(view.sockets[0].devices.isEmpty)
        #expect(view.unplaced.count == 1)
        #expect(view.unplaced[0].devices.map(\.id) == ["storage"])
    }
    @Test func legacyConflictingCompanionAssignmentsStayUnplaced() {
        var configuration = PortConfiguration()
        let right = PhysicalPort(name: "Right", side: .right)
        configuration.ports = [port, right]
        configuration.assignments = [
            PortAssignment(modelIdentifier: "FixtureMac", registryPath: "fixture://usb2", physicalPortID: port.id),
            PortAssignment(modelIdentifier: "FixtureMac", registryPath: "fixture://usb3", physicalPortID: right.id)
        ]
        let view = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(view.sockets.allSatisfy { $0.devices.isEmpty })
        #expect(view.unplaced.count == 1)
    }
    @Test func missingConnectorDoesNotLookEmptyAndDevicesRemainVisible() {
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        let missing = TopologySnapshot(nodes: snapshot.nodes, modelIdentifier: "FixtureMac")
        let view = PhysicalTopology(snapshot: missing, configuration: configuration)
        #expect(view.sockets[0].status == "Connection unavailable")
        #expect(view.unplaced.flatMap(\.devices).map(\.id) == ["storage"])
    }
    @Test func matchingConnectorAgainMovesItsAssignmentInsteadOfDuplicatingIt() {
        var configuration = PortConfiguration()
        let right = PhysicalPort(name: "Right", side: .right)
        configuration.ports = [port, right]
        configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        configuration.assignConnector(connector, snapshot: snapshot, to: right.id)
        let view = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(view.sockets.first { $0.id == port.id }?.devices.isEmpty == true)
        #expect(view.sockets.first { $0.id == right.id }?.devices.map(\.id) == ["storage"])
        #expect(configuration.assignments.count == 1)
    }
    @Test func versionOneSettingsMigrateWithoutLosingManualLabels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ports.json")
        let json = """
        {"schemaVersion":1,"ports":[{"id":"00000000-0000-0000-0000-000000000001","name":"Custom left","side":"left"}],"assignments":[]}
        """
        try Data(json.utf8).write(to: url)
        let migrated = try ConfigurationStore(url: url).load()
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.ports.first?.name == "Custom left")
    }
}
