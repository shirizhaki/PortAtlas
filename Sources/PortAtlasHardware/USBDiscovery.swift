import Foundation
import IOKit
import IOUSBHost
import PortAtlasCore

public enum DiscoveryError: LocalizedError {
    case registry(String, kern_return_t)
    public var errorDescription: String? {
        switch self { case let .registry(operation, code): return "\(operation) failed (IOKit \(code))." }
    }
}

/// Only reads public IORegistry APIs. It never opens, claims, resets or configures a device.
public enum USBDiscovery {
    public static func snapshot() throws -> TopologySnapshot {
        var nodes: [HardwareNode] = []
        var connectors: [String: HardwareConnector] = [:]
        let maximumSpeeds = TransportDiscovery.maximumLinkSpeeds()
        // Enumerate explicit physical IOPorts, including USB-A when the host exposes it.
        var portIterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPort"), &portIterator) == KERN_SUCCESS {
            defer { IOObjectRelease(portIterator) }
            while case let entry = IOIteratorNext(portIterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                let path = registryPath(entry)
                if let connector = connector(at: path, maximumSpeeds: maximumSpeeds) { connectors[path] = connector }
            }
        }
        let routes = TransportDiscovery.routes(connectors: Array(connectors.keys))
        nodes.append(contentsOf: routes.nodes)
        nodes.append(contentsOf: TransportDiscovery.displayNodes(connectors: Array(connectors.keys), routers: routes.nodes))
        for (className, kind) in [("AppleUSBHostController", NodeKind.controller), ("AppleUSBHostPort", .port), ("IOUSBHostDevice", .device)] {
            var iterator: io_iterator_t = 0
            let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
            guard status == KERN_SUCCESS else { throw DiscoveryError.registry("USB discovery", status) }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                // Downstream hub ports are represented by their actual device ancestry.
                if kind == .port && nearestAncestor(service, classes: ["IOUSBHostDevice"]) != nil { continue }
                guard let id = entryID(service) else { continue }
                let properties = properties(service)
                let parentClasses = kind == .device
                    ? ["IOUSBHostDevice", "AppleUSBHostPort", "AppleUSBHostController"]
                    : ["AppleUSBHostController"]
                let parentID = kind == .controller ? routes.controllerParents[id] : nearestAncestor(service, classes: parentClasses, skipHubPorts: true)
                let rawClass = number(properties, "bDeviceClass")
                let actualKind: NodeKind = kind == .device && rawClass == 9 ? .hub : kind
                let portNumber = number(properties, "PortNumber") ?? number(properties, "port")
                let protocols = [("UsbProtocol (2.0)", "USB2"), ("UsbProtocol (3.x)", "USB3")]
                    .compactMap { (properties[$0.0] as? NSNumber)?.boolValue == true ? $0.1 : nil }
                var connectorPath: String?
                if kind == .port, let path = string(properties, "UsbIOPort"),
                   let connector = connector(at: path, maximumSpeeds: maximumSpeeds) {
                    connectorPath = path
                    let reported = Set(connector.reportedTransports + (connectors[path]?.reportedTransports ?? []) + protocols)
                    connectors[path] = HardwareConnector(id: path, number: connector.number, connectionActive: connector.connectionActive,
                                                        reportedTransports: reported.sorted(), links: connector.links, powerContractWatts: connector.powerContractWatts, laneDetails: connector.laneDetails, kind: connector.kind, power: connector.power, cable: connector.cable, maximumLinkSpeed: connector.maximumLinkSpeed, controllerUUID: connector.controllerUUID)
                }
                let name: String
                if kind == .port { name = portNumber.map { "Logical port \($0)" } ?? registryName(service) }
                else { name = string(properties, "USB Product Name") ?? string(properties, "kUSBProductString") ?? registryName(service) }
                // Use the exported IOUSBHost key and its enum, not legacy Device Speed values.
                let speed = kind == .device ? number(properties, IOUSBHostMatchingPropertyKey.speed.rawValue).flatMap(LinkSpeed.hostEnumeration) : nil
                let power = [("kUSBBusCurrentAllocation", "Allocated bus current"), ("kUSBHubPowerSupply", "Hub downstream supply")]
                    .compactMap { key, label -> PowerFact? in
                        guard let value = number(properties, key), value >= 0 else { return nil }
                        return PowerFact(label: label, milliamps: value, source: key)
                    }
                nodes.append(HardwareNode(id: id, name: name, kind: actualKind, parentID: parentID,
                    registryPath: registryPath(service), manufacturer: string(properties, "USB Vendor Name"),
                    vendorID: number(properties, "idVendor"), productID: number(properties, "idProduct"),
                    locationID: (properties["locationID"] as? NSNumber)?.uint32Value,
                    speed: speed, power: power, portNumber: portNumber,
                    connectorPath: connectorPath, interfaceClasses: kind == .device ? interfaceClasses(service) : nil,
                    isUSB4Tunnel: (properties["UsbTunnel"] as? NSNumber)?.boolValue,
                    transport: kind == .port && !protocols.isEmpty
                        ? protocols.map { $0 == "USB2" ? "USB 2" : "USB 3" }.joined(separator: " / ") + " branch" : nil))
            }
        }
        return TopologySnapshot(nodes: nodes, modelIdentifier: modelIdentifier(), notices: [
            "USB ancestry and available port transport state. Missing display, power and Thunderbolt route evidence remains unassigned."
        ], connectors: connectors.values.sorted { $0.id < $1.id },
           storage: StorageDiscovery.volumes(deviceIDs: Set(nodes.filter { $0.kind == .device }.map(\.id))),
           formFactor: formFactor(), powerStatus: PowerDiscovery.status(),
           thunderboltDevices: [])
    }

    private static func connector(at path: String, maximumSpeeds: [Int: LinkSpeed]) -> HardwareConnector? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let values = properties(entry)
        guard IOObjectConformsTo(entry, "IOPort") != 0, let type = string(values, "PortTypeDescription") else { return nil }
        guard let kind = ConnectorKind.detected(portType: type, builtIn: (values["BuiltIn"] as? NSNumber)?.boolValue, appleSilicon: isAppleSilicon) else { return nil }
        let power = kind == .usbC || kind == .magSafe ? PowerDiscovery.contract(of: entry) : nil
        return HardwareConnector(id: path, number: number(values, "PortNumber"),
                                 connectionActive: PowerDiscovery.connectionActive(of: entry) ?? (values["ConnectionActive"] as? NSNumber)?.boolValue,
                                 reportedTransports: values["TransportsSupported"] as? [String] ?? [],
                                 links: TransportDiscovery.activeLinks(of: entry),
                                 powerContractWatts: power?.contractWatts,
                                 laneDetails: kind == .usbC ? TransportDiscovery.laneDetails(number: number(values, "PortNumber")) : [],
                                 kind: kind, power: power, cable: kind == .usbC ? PowerDiscovery.cable(of: entry) : nil, maximumLinkSpeed: kind == .usbC ? number(values, "PortNumber").flatMap { maximumSpeeds[$0] } : nil, controllerUUID: kind == .usbC ? PowerOutputDiscovery.controllerUUID(of: entry) : nil)
    }

    private static func interfaceClasses(_ device: io_registry_entry_t) -> [Int] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var classes: Set<Int> = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
               let value = number(properties(child), "bInterfaceClass") { classes.insert(value) }
        }
        return classes.sorted()
    }

    private static func formFactor() -> MacFormFactor {
        // A built-in battery supplies the laptop silhouette, independent of capabilities.
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != 0 else { return .desktop }
        IOObjectRelease(battery); return .laptop
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    public static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(cString: buffer)
    }

    private static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
        var result: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &result, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let result else { return [:] }
        return result.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:]
    }
    private static func number(_ values: [String: Any], _ key: String) -> Int? { (values[key] as? NSNumber)?.intValue }
    private static func string(_ values: [String: Any], _ key: String) -> String? {
        guard let value = values[key] as? String, !value.isEmpty else { return nil }; return value
    }
    private static func entryID(_ entry: io_registry_entry_t) -> String? {
        var value: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(entry, &value) == KERN_SUCCESS ? String(value) : nil
    }
    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        return IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS ? String(cString: buffer) : "Unknown device"
    }
    private static func registryPath(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 512)
        return IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS ? String(cString: buffer) : ""
    }
    private static func nearestAncestor(_ entry: io_registry_entry_t, classes: [String], skipHubPorts: Bool = false) -> String? {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else { return nil }
        var visited: Set<String> = []
        while current != 0 {
            let id = entryID(current)
            guard let id, visited.insert(id).inserted else { IOObjectRelease(current); return nil }
            for name in classes where IOObjectConformsTo(current, name) != 0 {
                if skipHubPorts && name == "AppleUSBHostPort" && nearestAncestor(current, classes: ["IOUSBHostDevice"]) != nil { continue }
                IOObjectRelease(current); return id
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if status != KERN_SUCCESS { return nil }
            current = parent
        }
        return nil
    }
}
