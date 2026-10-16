import Foundation
import IOKit
import IOKit.ps
import PortAtlasCore

/// Public power-source APIs plus optional registry schemas isolated in this adapter. Source integers and controller indices
/// are not mapped to USB-C sockets because the public contract does not define that mapping.
enum PowerDiscovery {
    // Adapted from WhatPort's CCReader / ChargerReader (MIT, Darryl Morley).
    // See ThirdPartyNotices/WhatPort-LICENSE.txt and Docs/ThirdParty.md.
    static func connectionActive(of port: io_registry_entry_t) -> Bool? {
        let values = descendants(of: port, className: "IOPortTransportStateCC")
            .compactMap { ($0["Active"] as? NSNumber)?.boolValue }
        let states = Set(values)
        return states.count == 1 ? states.first : nil
    }

    static func contract(of port: io_registry_entry_t) -> ConnectorPower? {
        parseSources(descendants(of: port, className: "IOPortFeaturePowerSource"))
    }

    static func parseSources(_ properties: [[String: Any]]) -> ConnectorPower? {
        let sources = properties.filter { $0["PowerSourceName"] as? String == "USB-PD" }
        guard sources.count == 1, let source = sources.first else { return nil }
        let selected = source["WinningPowerSourceOption"] as? [String: Any]
        func positive(_ values: [String: Any]?, _ key: String) -> Int? {
            guard let n = (values?[key] as? NSNumber)?.intValue, n > 0 else { return nil }
            return n
        }
        let mw = positive(selected, "Max Power (mW)")
        let advertised = (source["PowerSourceOptions"] as? [[String: Any]] ?? [])
            .compactMap { positive($0, "Max Power (mW)") }.max()
        return ConnectorPower(contractWatts: mw.flatMap { $0 >= 1000 ? $0 / 1000 : nil },
            voltageMillivolts: mw == nil ? nil : positive(selected, "Voltage (mV)"),
            currentMilliamps: mw == nil ? nil : positive(selected, "Max Current (mA)"),
            advertisedWatts: advertised.map { $0 / 1000 })
    }

    private static func descendants(of port: io_registry_entry_t, className: String?) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(port, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if let className, IOObjectConformsTo(child, className) == 0 { continue }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let properties, let values = properties.takeRetainedValue() as NSDictionary as? [String: Any] { result.append(values) }
        }
        return result
    }

    static func cable(of port: io_registry_entry_t) -> CableIdentity? {
        guard connectionActive(of: port) == true else { return nil }
        return parseCable(descendants(of: port, className: nil))
    }
    // Adapted from WhatPort CCReader's SOP' metadata decoding (MIT).
    static func parseCable(_ values: [[String: Any]]) -> CableIdentity? {
        let identities = values.compactMap { value -> CableIdentity? in
            guard value["ComponentName"] as? String == "SOP'",
                  let metadata = value["Metadata"] as? [String: Any],
                  let type = metadata["Product Type Description"] as? String,
                  ["Active Cable", "Passive Cable"].contains(type) else { return nil }
            let revision = (value["Specification Revision"] as? NSNumber)?.intValue
            return CableIdentity(productType: type, pdRevision: revision.flatMap { (1...3).contains($0) ? $0 : nil })
        }
        return identities.count == 1 ? identities.first : nil
    }

    static func status() -> MacPowerStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return MacPowerStatus() }
        let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let external: Bool? = type == kIOPSACPowerValue ? true : (type == kIOPSBatteryPowerValue ? false : nil)
        var charging: Bool?
        if let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let values = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                charging = (values[kIOPSIsChargingKey] as? NSNumber)?.boolValue
                break
            }
        }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let watts = (adapter?[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue
        let fallback = MacPowerStatus(externalPower: external, isCharging: charging, adapterWatts: watts)
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != 0 else { return fallback }
        defer { IOObjectRelease(battery) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(battery, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties, let values = properties.takeRetainedValue() as NSDictionary as? [String: Any] else { return fallback }
        return status(overriding: fallback, battery: values)
    }
    /// Battery-controller flags avoid the lag in the cached IOPS description.
    static func status(overriding fallback: MacPowerStatus, battery: [String: Any]) -> MacPowerStatus {
        func flag(_ key: String) -> Bool? {
            guard let value = battery[key] as? NSNumber, [0, 1].contains(value.doubleValue) else { return nil }
            return value.boolValue
        }
        let external = flag("ExternalConnected") ?? fallback.externalPower
        return MacPowerStatus(externalPower: external,
            isCharging: external == false ? false : (flag("IsCharging") ?? fallback.isCharging),
            adapterWatts: external == false ? nil : fallback.adapterWatts)
    }
}
