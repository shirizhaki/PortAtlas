#if DEBUG
import Foundation
import PortAtlasCore

/// Invented hardware for screenshots and design review, so no real device, drive or
/// volume name appears. Debug builds only: launch with `-demoTopology YES`.
/// Demo mode never reads or writes the saved port and component settings.
enum DemoTopology {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoTopology") }

    private static let magSafe = HardwareConnector(id: "demo://magsafe", connectionActive: true, kind: .magSafe,
        power: ConnectorPower(contractWatts: 96, voltageMillivolts: 20000, currentMilliamps: 4800, advertisedWatts: 140))
    private static let thunderbolt = LinkSpeed(megabitsPerSecond: 40000, source: "Demo")
    private static let left1 = HardwareConnector(id: "demo://usb-c-1", number: 1, connectionActive: true,
        reportedTransports: ["USB2", "USB3", "CIO", "DisplayPort"], kind: .usbC, maximumLinkSpeed: thunderbolt)
    private static let left2 = HardwareConnector(id: "demo://usb-c-2", number: 2, connectionActive: false,
        reportedTransports: ["USB2", "USB3", "CIO", "DisplayPort"], kind: .usbC, maximumLinkSpeed: thunderbolt)
    private static let right1 = HardwareConnector(id: "demo://usb-c-3", number: 3, connectionActive: true,
        reportedTransports: ["USB2", "USB3", "CIO", "DisplayPort"],
        links: [PortTransportLink(id: "demo-link", kind: .thunderboltUSB4, detail: "40 Gb/s", registryPath: "demo://link")],
        kind: .usbC, cable: CableIdentity(productType: "Passive Cable", pdRevision: 3), maximumLinkSpeed: thunderbolt)
    private static let hdmi = HardwareConnector(id: "demo://hdmi", connectionActive: false, kind: .hdmi)

    private static func speed(_ megabits: Double) -> LinkSpeed { LinkSpeed(megabitsPerSecond: megabits, source: "Demo") }
    /// A Mac controller with the USB 2 and USB 3 branches of one connector.
    private static func controller(_ index: Int, _ connector: HardwareConnector) -> [HardwareNode] {
        let id = "demo-controller-\(index)"
        return [HardwareNode(id: id, name: "Controller", kind: .controller),
                HardwareNode(id: "\(id)-usb2", name: "Logical port 1", kind: .port, parentID: id, registryPath: "demo://\(id)/usb2",
                             portNumber: 1, connectorPath: connector.id, transport: "USB 2 branch"),
                HardwareNode(id: "\(id)-usb3", name: "Logical port 2", kind: .port, parentID: id, registryPath: "demo://\(id)/usb3",
                             portNumber: 2, connectorPath: connector.id, transport: "USB 3 branch")]
    }

    static let snapshot: TopologySnapshot = {
        var nodes = controller(1, left1) + controller(2, left2) + controller(3, right1)
        nodes += [
            HardwareNode(id: "demo-portable-ssd", name: "Portable SSD", kind: .device, parentID: "demo-controller-1-usb3",
                         registryPath: "demo://portable-ssd", manufacturer: "Example Storage", speed: speed(10000), interfaceClasses: [8]),
            HardwareNode(id: "demo-dock", name: "Thunderbolt Dock", kind: .hub, registryPath: "demo://dock",
                         manufacturer: "Example Labs", speed: speed(40000), connectorPath: right1.id, transport: "Thunderbolt router"),
            HardwareNode(id: "demo-dock-usb", name: "Dock USB controller", kind: .controller, parentID: "demo-dock"),
            HardwareNode(id: "demo-dock-port", name: "Logical port 1", kind: .port, parentID: "demo-dock-usb",
                         registryPath: "demo://dock/port-1", portNumber: 1),
            HardwareNode(id: "demo-hub", name: "USB Hub", kind: .hub, parentID: "demo-dock-port", registryPath: "demo://dock/hub",
                         speed: speed(5000)),
            HardwareNode(id: "demo-keyboard", name: "Keyboard", kind: .device, parentID: "demo-hub", registryPath: "demo://dock/keyboard",
                         manufacturer: "Example Input", speed: speed(12), interfaceClasses: [3]),
            HardwareNode(id: "demo-audio", name: "Audio Interface", kind: .device, parentID: "demo-hub", registryPath: "demo://dock/audio",
                         manufacturer: "Example Audio", speed: speed(480), interfaceClasses: [1]),
            HardwareNode(id: "demo-nvme", name: "NVMe SSD", kind: .device, parentID: "demo-dock", registryPath: "demo://dock/nvme",
                         manufacturer: "Example Storage", speed: speed(40000), interfaceClasses: [8], transport: "PCIe / NVMe storage"),
            HardwareNode(id: "display-9001", name: "5K Display", kind: .device, parentID: "demo-dock", registryPath: "demo://dock/display",
                         connectorPath: right1.id, transport: "DisplayPort tunnel · 8.1 Gbps (HBR3)/lane × 4", displayID: 9001)
        ]
        let terabyte: Int64 = 1_000_000_000_000
        return TopologySnapshot(nodes: ThunderboltBranches.attach(nodes), modelIdentifier: "Mac15,6",
            connectors: [magSafe, left1, left2, right1, hdmi],
            storage: [StorageVolume(id: "demo://volume-backup", deviceID: "demo-portable-ssd", name: "Backup", totalBytes: terabyte, availableBytes: terabyte * 62 / 100),
                      StorageVolume(id: "demo://volume-projects", deviceID: "demo-nvme", name: "Projects", totalBytes: 2 * terabyte, availableBytes: terabyte * 92 / 100)]
                .compactMap { $0 },
            formFactor: .laptop, powerStatus: MacPowerStatus(externalPower: true, isCharging: true, adapterWatts: 96),
            product: .macBook, productName: "MacBook Pro")
    }()

    static let displays: [DisplayDevice] = {
        let fiveK = DisplayResolution(width: 5120, height: 2880)
        return [DisplayDevice(id: 9001, name: "5K Display", width: 2560, height: 1440, refreshRate: 60,
                              signal: fiveK.flatMap { DisplaySignal(resolution: $0, refreshRate: 60) },
                              nativeResolution: fiveK, renderedResolution: fiveK)]
    }()

    static let configuration: PortConfiguration = {
        var configuration = PortConfiguration()
        configuration.ports = [PhysicalPort(name: "Left 1", side: .left), PhysicalPort(name: "Left 2", side: .left),
                               PhysicalPort(name: "Right 1", side: .right)]
        for (port, connector) in zip(configuration.ports, [left1, left2, right1]) {
            configuration.assignConnector(connector, snapshot: snapshot, to: port.id)
        }
        return configuration
    }()
}
#endif
