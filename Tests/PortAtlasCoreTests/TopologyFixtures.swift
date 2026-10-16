import PortAtlasCore
import Foundation

extension TopologySnapshot {
    static let demo = TopologySnapshot(nodes: [
        HardwareNode(id: "demo-controller", name: "USB controller", kind: .controller),
        HardwareNode(id: "demo-port", name: "Logical port 1", kind: .port, parentID: "demo-controller", registryPath: "demo://port-1", portNumber: 1, connectorPath: "demo://socket-1"),
        HardwareNode(id: "demo-hub", name: "Desktop USB hub", kind: .hub, parentID: "demo-port", manufacturer: "Example manufacturer", speed: LinkSpeed(megabitsPerSecond: 5000, source: "Synthetic example")),
        HardwareNode(id: "demo-ssd", name: "External SSD", kind: .device, parentID: "demo-hub", speed: LinkSpeed(megabitsPerSecond: 5000, source: "Synthetic example")),
        HardwareNode(id: "demo-keyboard", name: "Keyboard", kind: .device, parentID: "demo-hub", speed: LinkSpeed(megabitsPerSecond: 12, source: "Synthetic example")),
        HardwareNode(id: "demo-mouse", name: "Mouse", kind: .device, parentID: "demo-hub", speed: LinkSpeed(megabitsPerSecond: 1.5, source: "Synthetic example")),
        HardwareNode(id: "demo-port-2", name: "Logical port 2", kind: .port, parentID: "demo-controller", registryPath: "demo://port-2", portNumber: 2, connectorPath: "demo://socket-2"),
        HardwareNode(id: "demo-port-3", name: "Logical port 3", kind: .port, parentID: "demo-controller", registryPath: "demo://port-3", portNumber: 3, connectorPath: "demo://socket-3")
    ], modelIdentifier: "Example Mac", notices: ["Demo mode — all devices and speeds are examples."], connectors: [
        HardwareConnector(id: "demo://socket-1", number: 1, connectionActive: true),
        HardwareConnector(id: "demo://socket-2", number: 2, connectionActive: false),
        HardwareConnector(id: "demo://socket-3", number: 3, connectionActive: false)
    ])
}

extension PortConfiguration {
    static let demo: PortConfiguration = {
        var configuration = PortConfiguration()
        configuration.ports = [PhysicalPort(name: "Left · near", side: .left),
                               PhysicalPort(name: "Left · far", side: .left),
                               PhysicalPort(name: "Right", side: .right)]
        for (port, connector) in zip(configuration.ports, TopologySnapshot.demo.connectors) {
            configuration.assignConnector(connector, snapshot: .demo, to: port.id)
        }
        return configuration
    }()
}
