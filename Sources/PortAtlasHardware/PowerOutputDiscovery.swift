import Foundation
import IOKit
import PortAtlasCore

/// Adapted from WhatPort PowerReader / SMCPowerReader (MIT). Outputs are scoped to
/// a host connector. No downstream charging attribution or PD protocol inference.
enum PowerOutputDiscovery {
    static func normalizedUUID(_ value: String?) -> String? {
        guard let value else { return nil }
        let hex = value.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              hex.contains(where: { $0 != "0" }) else { return nil }
        return hex
    }
    static func controllerUUID(of entry: io_registry_entry_t) -> String? {
        var current = entry; IOObjectRetain(current)
        for _ in 0..<12 {
            var name = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(current, &name) == KERN_SUCCESS {
                let cls = String(cString: name)
                if cls == "AppleHPMDevice" || cls.hasPrefix("AppleHPMDeviceHAL") {
                    let uuid = IORegistryEntryCreateCFProperty(current, "UUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                    IOObjectRelease(current)
                    return normalizedUUID(uuid)
                }
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return nil }
            current = parent
        }
        IOObjectRelease(current)
        return nil
    }
    static func resolve(_ entries: [[String: Any]], smc: [SMCInputReader.PortReading],
                        connectors: [HardwareConnector], at date: Date) -> [PortPowerOutput] {
        let usb = connectors.filter { $0.kind == .usbC }
        let numbers = Dictionary(grouping: usb.compactMap { $0.number }, by: { $0 }).mapValues(\.count)
        let uuids = Dictionary(grouping: usb.compactMap { normalizedUUID($0.controllerUUID) }, by: { $0 }).mapValues(\.count)
        let channels = Dictionary(grouping: smc, by: \.uuid)
        let reports = Dictionary(grouping: entries.compactMap { entry -> (Int, [String: Any])? in
            guard let index = number(entry["PortIndex"], range: 1...32), index.rounded() == index else { return nil }
            return (Int(index), entry)
        }, by: { $0.0 })
        return usb.compactMap { connector in
            guard connector.connectionActive == true, (connector.powerContractWatts ?? 0) <= 0 else { return nil }
            let report = connector.number.flatMap { numbers[$0] == 1 && reports[$0]?.count == 1 ? reports[$0]?.first?.1 : nil }
            let configured = report.flatMap(configuredLimit)
            if let uuid = normalizedUUID(connector.controllerUUID), uuids[uuid] == 1,
               let matches = channels[uuid] {
                // Conflicting channels never fall back to a guessed D-index.
                guard matches.count == 1, let channel = matches.first else { return nil }
                // A valid live zero suppresses an old firmware-batched positive report.
                return PortPowerOutput(connectorID: connector.id, watts: channel.watts, volts: channel.volts, amps: channel.amps,
                    configuredWatts: configured, source: "AppleSMC output rails · hardware identity matched", sampledAt: date)
            }
            guard let report,
                  let mw = number(report["Watts"], range: 10...100_000),
                  let mv = number(report["AdapterVoltage"], range: 4000...30000),
                  let ma = number(report["Current"], range: 1...10000) else { return nil }
            let watts = mw / 1000, calculated = mv * ma / 1_000_000
            guard abs(watts - calculated) <= max(1, watts * 0.25) else { return nil }
            return PortPowerOutput(connectorID: connector.id, watts: watts, volts: mv / 1000, amps: ma / 1000,
                configuredWatts: configured, source: "AppleSmartBattery.PowerOutDetails · updates may be delayed", sampledAt: date)
        }
    }
    private static func configuredLimit(_ entry: [String: Any]) -> Double? {
        guard let mv = number(entry["ConfiguredVoltage"], range: 4000...30000),
              let ma = number(entry["ConfiguredCurrent"], range: 1...10000) else { return nil }
        let watts = mv * ma / 1_000_000
        return watts <= 100 ? watts : nil
    }
    private static func number(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, range.contains(n.doubleValue) else { return nil }
        return n.doubleValue
    }
}
