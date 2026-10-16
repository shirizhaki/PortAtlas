import Testing
import PortAtlasCore

struct PowerRoutingTests {
    @Test func magSafeExistsOnlyWhenReportedAndDoesNotPersistCalibration() {
        let usb = HardwareConnector(id: "usb", connectionActive: false)
        let mag = HardwareConnector(id: "mag", number: 1, connectionActive: false, kind: .magSafe)
        let config = PortConfiguration()
        let absent = PhysicalTopology(snapshot: TopologySnapshot(nodes: [], modelIdentifier: "Fixture", connectors: [usb]), configuration: config)
        #expect(absent.sockets.isEmpty)
        let present = PhysicalTopology(snapshot: TopologySnapshot(nodes: [], modelIdentifier: "Fixture", connectors: [usb, mag]), configuration: config)
        #expect(present.sockets.count == 1)
        #expect(present.sockets.first?.port.side == .left)
        #expect(present.sockets.first?.isMagSafe == true)
        #expect(present.sockets.first?.status == "Not connected")
        #expect(present.unplaced.map(\.id) == ["usb"])
        #expect(config.ports.isEmpty && config.assignments.isEmpty)
    }
    @Test func displayAndInputPowerShareOneSocket() {
        let usb = HardwareConnector(id: "usb", connectionActive: true, links: [
            PortTransportLink(id: "dp", kind: .displayPort, registryPath: "fixture://dp")
        ], powerContractWatts: 60)
        let mag = HardwareConnector(id: "mag", connectionActive: true, kind: .magSafe)
        let snapshot = TopologySnapshot(nodes: [], modelIdentifier: "Fixture", connectors: [usb, mag],
            powerStatus: MacPowerStatus(externalPower: true, isCharging: false))
        #expect(snapshot.powerRoute?.connectorID == "usb")
        #expect(snapshot.powerRoute?.evidence == .reportedContract)
        #expect(snapshot.connectors.first?.links.first?.kind == .displayPort)
    }
    @Test func ambiguousAndStaleContractsNeverChooseAnInput() {
        let a = HardwareConnector(id: "a", connectionActive: true, powerContractWatts: 60)
        let b = HardwareConnector(id: "b", connectionActive: true, powerContractWatts: 100)
        #expect(PowerRouting.resolve(connectors: [a,b], externalPower: true) == nil)
        #expect(PowerRouting.resolve(connectors: [a], externalPower: false) == nil)
        #expect(PowerRouting.resolve(connectors: [a], externalPower: nil) == nil)
        let stale = HardwareConnector(id: "a", connectionActive: false, powerContractWatts: 60)
        #expect(PowerRouting.resolve(connectors: [stale], externalPower: true) == nil)
    }
    @Test func magSafeInferenceRequiresEveryUSBSocketToBeExplicitlyInactive() {
        let mag = HardwareConnector(id: "mag", connectionActive: true, kind: .magSafe,
            power: ConnectorPower(advertisedWatts: 140))
        let empty = HardwareConnector(id: "usb", connectionActive: false)
        let connected = HardwareConnector(id: "usb", connectionActive: true)
        let unknown = HardwareConnector(id: "usb")
        #expect(PowerRouting.resolve(connectors: [mag, empty], externalPower: true)?.evidence == .onlyConnectedInput)
        #expect(mag.powerContractWatts == nil)
        #expect(PowerRouting.resolve(connectors: [mag, connected], externalPower: true) == nil)
        #expect(PowerRouting.resolve(connectors: [mag, unknown], externalPower: true) == nil)
        #expect(PowerRouting.resolve(connectors: [mag], externalPower: true) == nil)
    }
    @Test func magSafePrecedesManualLeftPortsAndDoesNotStealTheirAssignment() {
        let mag = HardwareConnector(id: "mag", number: 1, kind: .magSafe)
        let usb = HardwareConnector(id: "usb", number: 1)
        let port = PhysicalPort(name: "Left 1", side: .left)
        let snapshot = TopologySnapshot(nodes: [], modelIdentifier: "Fixture", connectors: [mag, usb])
        var config = PortConfiguration(); config.ports = [port]
        config.assignConnector(usb, snapshot: snapshot, to: port.id)
        let result = PhysicalTopology(snapshot: snapshot, configuration: config)
        #expect(result.sockets.count == 2)
        #expect(result.sockets[0].isMagSafe)
        #expect(result.sockets[1].connectors.map(\.id) == ["usb"])
        #expect(result.unplaced.isEmpty)
    }
}
