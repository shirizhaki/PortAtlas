import Testing
import PortAtlasCore

struct ConnectionFactsTests {
    @Test func thunderboltRateUsesCurrentWidthAndRejectsUnknownEncodings() {
        #expect(LinkSpeed.thunderbolt(speedCode: 4, width: 2)?.megabitsPerSecond == 40000)
        #expect(LinkSpeed.thunderbolt(speedCode: 4, width: 1)?.megabitsPerSecond == 20000)
        #expect(LinkSpeed.thunderbolt(speedCode: 8, width: 2)?.megabitsPerSecond == 20000)
        #expect(LinkSpeed.thunderbolt(speedCode: 2, width: 2)?.megabitsPerSecond == 80000)
        #expect(LinkSpeed.thunderbolt(speedCode: 0, width: 0) == nil)
        #expect(LinkSpeed.thunderbolt(speedCode: 12, width: 2) == nil)
        #expect(LinkSpeed.thunderbolt(speedCode: 2, width: 3) == nil)
    }
    @Test func hardwareProtocolsDoNotInventThunderboltGenerationOrUSBRate() {
        let connector = HardwareConnector(id: "fixture://port", reportedTransports: ["CC", "USB2", "USB3", "CIO", "DisplayPort"])
        #expect(connector.reportedSupportLabel == "USB 2 · USB 3 · DisplayPort")
        #expect(connector.reportedSupportLabel?.contains("Thunderbolt") == false)
        #expect(connector.reportedSupportLabel?.contains("Gb/s") == false)
        #expect(HardwareConnector(id: "unknown", reportedTransports: ["CIO", "FutureTransport"]).reportedSupportLabel == nil)
        #expect(HardwareConnector(id: "usb2", reportedTransports: ["USB2"]).reportedSupportLabel == "USB 2")
    }
    @Test func videoOnlyConnectionIsNotShownAsAnEmptyUSBPort() {
        let connector = HardwareConnector(id: "fixture://port", connectionActive: true, links: [
            PortTransportLink(id: "video", kind: .displayPort, registryPath: "fixture://port/DisplayPort")
        ])
        let port = PhysicalPort(name: "Left", side: .left)
        let snapshot = TopologySnapshot(nodes: [HardwareNode(id: "p", name: "Root", kind: .port,
            registryPath: "fixture://logical", connectorPath: connector.id)], modelIdentifier: "FixtureMac", connectors: [connector])
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        let projected = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(projected.sockets[0].devices.isEmpty)
        #expect(projected.sockets[0].status == "Connected")
        #expect(projected.sockets[0].connectors[0].links[0].kind == .displayPort)
    }
    @Test func adapterRatingDoesNotMeanBatteryIsCharging() {
        let power = MacPowerStatus(externalPower: true, isCharging: false, adapterWatts: 65)
        #expect(power.label == "External power connected")
        #expect(power.adapterWatts == 65)
        #expect(MacPowerStatus(externalPower: false, isCharging: false).label == "On battery")
        #expect(MacPowerStatus(externalPower: true, isCharging: true).label == "Charging")
        #expect(MacPowerStatus(adapterWatts: -1).adapterWatts == nil)
        #expect(MacPowerStatus().label == "Power source unavailable")
    }
    @Test func connectorWithoutUSBRootsCanBeAssigned() {
        let connector = HardwareConnector(id: "fixture://video-only", connectionActive: true)
        let snapshot = TopologySnapshot(nodes: [], modelIdentifier: "FixtureMac", connectors: [connector])
        let port = PhysicalPort(name: "Right", side: .right)
        var configuration = PortConfiguration(); configuration.ports = [port]
        configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        let projected = PhysicalTopology(snapshot: snapshot, configuration: configuration)
        #expect(projected.unplaced.isEmpty)
        #expect(projected.sockets[0].connectors == [connector])
        #expect(projected.sockets[0].status == "Connected · USB device not reported")
        configuration.assignConnector(connector, snapshot: snapshot, to: nil)
        #expect(configuration.assignments.isEmpty)
    }
}
