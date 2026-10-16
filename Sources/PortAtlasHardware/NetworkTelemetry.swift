import Foundation
import IOKit
import PortAtlasCore

/// SDK-defined IONetworkController link properties, joined through actual service ancestry.
public enum NetworkTelemetry {
    public static func sample(deviceIDs: Set<String>) -> [NetworkLink] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOEthernetController"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [NetworkLink] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var current = service
            IOObjectRetain(current)
            var owner: String?, visited: Set<UInt64> = []
            for _ in 0..<64 {
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(current, &id) == KERN_SUCCESS, visited.insert(id).inserted else { break }
                if deviceIDs.contains(String(id)) { owner = String(id); break }
                var parent: io_registry_entry_t = 0
                guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
                IOObjectRelease(current); current = parent
            }
            IOObjectRelease(current)
            guard let owner else { continue }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props, let values = props.takeRetainedValue() as NSDictionary as? [String: Any] else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            result.append(parse(values, id: String(id), deviceID: owner, at: Date()))
        }
        return result
    }
    static func parse(_ values: [String: Any], id: String, deviceID: String, at date: Date) -> NetworkLink {
        // kIONetworkLinkValid=1, kIONetworkLinkActive=2. Absence is unknown.
        func number(_ key: String) -> Double? {
            guard let value = values[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        let flags = number("IOLinkStatus").flatMap { (0...Double(UInt32.max)).contains($0) ? UInt32($0) : nil }
        let active = flags.flatMap { $0 & 1 != 0 ? $0 & 2 != 0 : nil }
        let rate = number("IOLinkSpeed")
        return NetworkLink(id: id, deviceID: deviceID, isActive: active,
            bitsPerSecond: active == true ? rate.flatMap { $0.isFinite && $0 > 0 && $0 <= 1_000_000_000_000 ? $0 : nil } : nil,
            sampledAt: date)
    }
}
