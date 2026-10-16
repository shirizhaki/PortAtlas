import Foundation
import IOKit
import CoreGraphics
import PortAtlasCore

/// IORegistry compatibility adapter. Optional class/property schemas are kept here;
/// no device open, private framework, control request or controller-index mapping.
enum TransportDiscovery {
    /// Adapted from WhatPort's ThunderboltReader (MIT). Socket ID is the hardware
    /// connector number; host route-zero ancestry excludes a dock's own adapters.
    static func maximumLinkSpeeds() -> [Int: LinkSpeed] {
        var candidates: [Int: [LinkSpeed]] = [:]
        enumerate("IOThunderboltPort") { entry in
            guard isHostAdapter(entry), let report = maximumLinkSpeed(properties(entry)) else { return }
            candidates[report.number, default: []].append(report.speed)
        }
        // Dual-link adapters can repeat the socket. Conflicting reports stay unknown.
        return candidates.compactMapValues { reports in
            Set(reports.map(\.megabitsPerSecond)).count == 1 ? reports.first : nil
        }
    }
    static func maximumLinkSpeed(_ values: [String: Any]) -> (number: Int, speed: LinkSpeed)? {
        guard values["Description"] as? String == "Thunderbolt Port",
              let socket = values["Socket ID"] as? String, let number = Int(socket), number > 0,
              let mask = values["Supported Link Speed"] as? NSNumber, CFGetTypeID(mask) != CFBooleanGetTypeID(),
              let width = values["Supported Link Width"] as? NSNumber, CFGetTypeID(width) != CFBooleanGetTypeID(),
              let speed = LinkSpeed.thunderboltMaximum(speedMask: mask.intValue, width: width.intValue) else { return nil }
        return (number, speed)
    }
    private static func isHostAdapter(_ entry: io_registry_entry_t) -> Bool {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else { return false }
        var seen: Set<String> = []
        while current != 0 {
            guard let id = entryID(current), seen.insert(id).inserted else { IOObjectRelease(current); return false }
            if IOObjectConformsTo(current, "IOThunderboltSwitch") != 0 {
                let route = properties(current)["Route String"] as? NSNumber
                IOObjectRelease(current)
                return route.map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.uint64Value == 0 } ?? false
            }
            var next: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return false }
            current = next
        }
        return false
    }
    static func activeLinks(of port: io_registry_entry_t) -> [PortTransportLink] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(port, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        let hdmi = properties(port)["PortTypeDescription"] as? String == "HDMI"
        var links: [PortTransportLink] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOPortTransportState") != 0 else { continue }
            let values = properties(child)
            guard (values["Active"] as? NSNumber)?.boolValue == true, let id = entryID(child) else { continue }
            let kind: PortTransportLink.Kind
            switch values["TransportTypeDescription"] as? String {
            case "DisplayPort": kind = hdmi ? .hdmi : .displayPort
            case "CIO": kind = .thunderboltUSB4
            case "USB3": kind = .usb3
            default: continue
            }
            var details = ["DataRateDescription", "LinkRateDescription", "GenerationDescription"].compactMap { values[$0] as? String }
                .filter { !["Unknown", "No Link", ""].contains($0) }
            if let tunnels = values["TunneledTransportsProvisioned"] as? [String], !tunnels.isEmpty {
                details.append("Provisioned tunnels: " + tunnels.joined(separator: ", "))
            }
            let detail = hdmi || details.isEmpty ? nil : details.joined(separator: " · ")
            links.append(PortTransportLink(id: id, kind: kind, detail: detail, registryPath: path(child)))
        }
        return links.sorted { $0.id < $1.id }
    }
    struct Routes {
        var nodes: [HardwareNode] = []
        var controllerParents: [String: String] = [:]
    }

    /// Join independent registry trees only through explicit UID/entry-ID references.
    /// Hardware UIDs stay within this scan and are never stored in the snapshot.
    static func routes(connectors: [String]) -> Routes {
        var uidPorts: [UInt64: Set<String>] = [:]
        for connector in connectors {
            let port = IORegistryEntryFromPath(kIOMainPortDefault, connector)
            guard port != 0 else { continue }
            defer { IOObjectRelease(port) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(port, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                let values = properties(child)
                guard IOObjectConformsTo(child, "IOPortTransportState") != 0,
                      values["TransportTypeDescription"] as? String == "CIO",
                      (values["Active"] as? NSNumber)?.boolValue == true,
                      let uid = values["UID"] as? NSNumber else { continue }
                uidPorts[uid.uint64Value, default: []].insert(connector)
            }
        }
        var routers: [(id: String, parent: String?, path: String, name: String, vendor: String?, uid: UInt64?, speed: LinkSpeed?, transport: String)] = []
        enumerate("IOThunderboltSwitch") { entry in
            let values = properties(entry)
            guard let route = values["Route String"] as? NSNumber, route.uint64Value != 0,
                  let id = entryID(entry) else { return }
            routers.append((id, parentSwitch(entry), path(entry),
                values["Device Model Name"] as? String ?? "Thunderbolt / USB4 accessory",
                values["Device Vendor Name"] as? String, (values["UID"] as? NSNumber)?.uint64Value, upstreamSpeed(entry, values: values), IOObjectConformsTo(entry, "IOThunderboltSwitchUSB4") != 0 ? "USB4 router" : "Thunderbolt router"))
        }
        let ids = Set(routers.map(\.id))
        let uidCounts = Dictionary(grouping: routers.compactMap(\.uid), by: { $0 }).mapValues(\.count)
        var result = Routes()
        result.nodes = routers.map { router in
            let paths = router.uid.flatMap { uidCounts[$0] == 1 ? uidPorts[$0] : nil } ?? []
            return HardwareNode(id: router.id, name: router.name, kind: .hub,
                parentID: router.parent.flatMap { ids.contains($0) ? $0 : nil }, registryPath: router.path,
                manufacturer: router.vendor, speed: router.speed, connectorPath: paths.count == 1 ? paths.first : nil,
                transport: router.transport)
        }
        enumerate("AppleUSBHostController") { entry in
            if let id = entryID(entry), let parent = tunnelRouter(entry, externalIDs: ids) {
                result.controllerParents[id] = parent
            }
        }
        enumerate("IONVMeController") { entry in
            guard let id = entryID(entry), let parent = tunnelRouter(entry, externalIDs: ids) else { return }
            let values = properties(entry)
            result.nodes.append(HardwareNode(id: id, name: values["Model Number"] as? String ?? "NVMe storage",
                kind: .device, parentID: parent, registryPath: path(entry),
                manufacturer: values["Vendor Name"] as? String, interfaceClasses: [8], transport: "PCIe / NVMe storage"))
        }
        return result
    }

    static func displayNodes(connectors: [String], routers: [HardwareNode]) -> [HardwareNode] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &displays, &count) == .success else { return [] }
        let external = displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
        var candidates: [HardwareNode] = []
        for connector in connectors {
            let port = IORegistryEntryFromPath(kIOMainPortDefault, connector)
            guard port != 0 else { continue }
            defer { IOObjectRelease(port) }
            let hdmi = properties(port)["PortTypeDescription"] as? String == "HDMI"
            var iterator: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(port, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard IOObjectConformsTo(entry, "IOPortTransportStateDisplayPort") != 0 else { continue }
                let values = properties(entry)
                guard (values["Active"] as? NSNumber)?.boolValue == true,
                      (values["SinkCount"] as? NSNumber)?.intValue == 1,
                      let edid = values["EDID"] as? Data, let identity = DisplayIdentity(edid: edid) else { continue }
                let matches = external.filter {
                    CGDisplayVendorNumber($0) == identity.vendor && CGDisplayModelNumber($0) == identity.product &&
                    CGDisplaySerialNumber($0) == identity.serial
                }
                guard matches.count == 1, let display = matches.first else { continue }
                let tunneled = (values["Tunneled"] as? NSNumber)?.boolValue == true
                let upstream = routers.filter { $0.connectorPath == connector && $0.kind == .hub }
                // This records passage through the host-facing router, not the exact DP socket on a daisy chain.
                let parent = !hdmi && tunneled && upstream.count == 1 ? upstream.first?.id : nil
                let bytes = Array(edid)
                var name = "External display"
                for offset in stride(from: 54, through: 108, by: 18) {
                    if bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 3] == 0xfc,
                       let text = String(bytes: bytes[(offset + 5)..<(offset + 18)], encoding: .ascii) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { name = trimmed }
                    }
                }
                let rate = values["LinkRateDescription"] as? String
                let lanes = (values["LaneCount"] as? NSNumber)?.intValue
                var detail = hdmi ? "HDMI" : tunneled ? "DisplayPort tunnel" : "DisplayPort"
                if !hdmi, let rate, rate != "No Link" { detail += " · " + rate + "/lane" }
                if !hdmi, let lanes, lanes > 0 { detail += " × " + String(lanes) }
                candidates.append(HardwareNode(id: "display-" + String(display), name: name, kind: .device,
                    parentID: parent, registryPath: path(entry), connectorPath: connector,
                    transport: detail, displayID: display))
            }
        }
        // Duplicate EDIDs or competing routes stay in the unassigned screen list.
        let counts = Dictionary(grouping: candidates, by: \.id).mapValues(\.count)
        return candidates.filter { counts[$0.id] == 1 }
    }

    private static func upstreamSpeed(_ router: io_registry_entry_t, values: [String: Any]) -> LinkSpeed? {
        guard let upstream = values["Upstream Port Number"] as? NSNumber else { return nil }
        // The upstream adapter can be the router's parent in IOService.
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(router, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer { IOObjectRelease(parent) }
            let port = properties(parent)
            if IOObjectConformsTo(parent, "IOThunderboltPort") != 0,
               port["Description"] as? String == "Thunderbolt Port",
               (port["Port Number"] as? NSNumber)?.intValue == upstream.intValue,
               let speed = port["Current Link Speed"] as? NSNumber,
               let width = port["Current Link Width"] as? NSNumber {
                return LinkSpeed.thunderbolt(speedCode: speed.intValue, width: width.intValue)
            }
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(router, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOThunderboltPort") != 0 else { continue }
            let port = properties(child)
            guard port["Description"] as? String == "Thunderbolt Port",
                  (port["Port Number"] as? NSNumber)?.intValue == upstream.intValue,
                  let speed = port["Current Link Speed"] as? NSNumber,
                  let width = port["Current Link Width"] as? NSNumber else { continue }
            return LinkSpeed.thunderbolt(speedCode: speed.intValue, width: width.intValue)
        }
        return nil
    }

    static func laneDetails(number: Int?) -> [String] {
        guard let number else { return [] }
        var reports: [[String]] = []
        enumerate("AppleTypeCPhy") { entry in
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(parent) }
            guard let data = properties(parent)["port-number"] as? Data, data.count == 4 else { return }
            let portNumber = data.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            guard portNumber == number else { return }
            let values = properties(entry)
            let lanes = values["AppleTypeCPhyLane"] as? [String: Any] ?? [:]
            var details: [String] = []
            for name in ["Lane 0", "Lane 1"] {
                let lane = lanes[name] as? [String: Any] ?? [:]
                if let transport = lane["Transport"] as? String, !transport.isEmpty {
                    details.append(name + ": " + (transport == "CIO" ? "Thunderbolt / USB4" : transport))
                }
            }
            if let usb2 = values["AppleTypeCPhyUSB2"] as? [String: Any],
               let transport = usb2["Transport"] as? String, !transport.isEmpty {
                details.append("USB 2 channel: " + transport)
            }
            if !details.isEmpty { reports.append(details) }
        }
        return reports.count == 1 ? reports[0] : []
    }

    private static func enumerate(_ name: String, visit: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            visit(entry); IOObjectRelease(entry)
        }
    }

    private static func tunnelRouter(_ entry: io_registry_entry_t, externalIDs: Set<String>) -> String? {
        var current = entry
        IOObjectRetain(current)
        var seen: Set<String> = []
        while current != 0 {
            guard let id = entryID(current), seen.insert(id).inserted else { IOObjectRelease(current); return nil }
            if let reference = properties(current)["Thunderbolt Entry ID"] as? NSNumber {
                let target = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(reference.uint64Value))
                if target != 0 {
                    let router: String?
                    if IOObjectConformsTo(target, "IOThunderboltSwitch") != 0 { router = entryID(target) }
                    else if IOObjectConformsTo(target, "IOThunderboltPort") != 0 { router = parentSwitch(target) }
                    else { router = nil }
                    IOObjectRelease(target)
                    // The nearest explicit reference owns this PCI branch, including host references.
                    IOObjectRelease(current)
                    return router.flatMap { externalIDs.contains($0) ? $0 : nil }
                }
            }
            var next: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return nil }
            current = next
        }
        return nil
    }
    private static func parentSwitch(_ entry: io_registry_entry_t) -> String? {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else { return nil }
        var seen: Set<String> = []
        while current != 0 {
            guard let id = entryID(current), seen.insert(id).inserted else { IOObjectRelease(current); return nil }
            if IOObjectConformsTo(current, "IOThunderboltSwitch") != 0 { IOObjectRelease(current); return id }
            var next: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return nil }
            current = next
        }
        return nil
    }
    private static func entryID(_ entry: io_registry_entry_t) -> String? {
        var value: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(entry, &value) == KERN_SUCCESS ? String(value) : nil
    }
    private static func path(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 512)
        return IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS ? String(cString: buffer) : ""
    }
    private static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let value else { return [:] }
        return value.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:]
    }
}
