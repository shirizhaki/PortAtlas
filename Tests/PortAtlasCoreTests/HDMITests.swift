import Foundation
import Testing
import PortAtlasCore

struct HDMITests {
    @Test func hardwarePresenceCreatesEmptyPortWithoutModelTable() {
        for form in [MacFormFactor.laptop, .desktop] {
            let connector = HardwareConnector(id: "fixture://hdmi", connectionActive: false, kind: .hdmi)
            let snapshot = TopologySnapshot(nodes: [], modelIdentifier: "Unknown future Mac", connectors: [connector], formFactor: form)
            let config = PortConfiguration()
            let projection = PhysicalTopology(snapshot: snapshot, configuration: config)
            #expect(projection.sockets.count == 1)
            #expect(projection.sockets[0].isHDMI)
            #expect(projection.sockets[0].port.side == (form == .laptop ? .right : .back))
            #expect(projection.sockets[0].status == "Not connected")
            #expect(projection.unplaced.isEmpty)
            #expect(config.ports.isEmpty)
        }
        #expect(PhysicalTopology(snapshot: TopologySnapshot(nodes: [], modelIdentifier: "No HDMI"), configuration: PortConfiguration()).sockets.isEmpty)
    }

    @Test func manualPositionReplacesAutomaticPortAndPreservesDisplayRoute() {
        let hdmi = HardwareConnector(id: "fixture://hdmi", connectionActive: true,
            links: [PortTransportLink(id: "link", kind: .hdmi, registryPath: "fixture://link")], kind: .hdmi)
        let usb = HardwareConnector(id: "fixture://usb", connectionActive: true)
        let display = HardwareNode(id: "screen", name: "HDMI display", kind: .device, connectorPath: hdmi.id, transport: "HDMI", displayID: 10)
        let dockDisplay = HardwareNode(id: "dock-screen", name: "Dock display", kind: .device, connectorPath: usb.id, transport: "DisplayPort tunnel", displayID: 20)
        let snapshot = TopologySnapshot(nodes: [display, dockDisplay], modelIdentifier: "Fixture", connectors: [hdmi, usb])
        var config = PortConfiguration()
        let hdmiPort = PhysicalPort(name: "HDMI", side: .back)
        let usbPort = PhysicalPort(name: "USB-C", side: .left)
        config.ports = [usbPort, hdmiPort]
        config.assignConnector(hdmi, snapshot: snapshot, to: hdmiPort.id)
        config.assignConnector(usb, snapshot: snapshot, to: usbPort.id)
        let projection = PhysicalTopology(snapshot: snapshot, configuration: config)
        #expect(projection.sockets.count == 2)
        #expect(projection.sockets.first { $0.isHDMI }?.id == hdmiPort.id)
        #expect(projection.sockets.first { $0.isHDMI }?.devices.map(\.id) == [display.id])
        #expect(projection.sockets.first { !$0.isHDMI }?.devices.map(\.id) == [dockDisplay.id])
        #expect(snapshot.node(display.id)?.parentID == nil)
        #expect(projection.unplaced.isEmpty)
        #expect(hdmi.links[0].isDisplay && hdmi.links[0].label == "HDMI link active")
    }

    @Test func ambiguousConnectorsStayUnmappedAndCannotSupplyPower() {
        let a = HardwareConnector(id: "a", connectionActive: true, powerContractWatts: 60, kind: .hdmi)
        let b = HardwareConnector(id: "b", connectionActive: true, kind: .hdmi)
        let snapshot = TopologySnapshot(nodes: [], modelIdentifier: "Fixture", connectors: [a,b])
        let projection = PhysicalTopology(snapshot: snapshot, configuration: PortConfiguration())
        #expect(projection.sockets.isEmpty)
        #expect(projection.unplaced.count == 2)
        #expect(PowerRouting.resolve(connectors: [a,b], externalPower: true) == nil)
    }
}
