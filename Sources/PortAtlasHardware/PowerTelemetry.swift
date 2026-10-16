import Foundation
import IOKit
import PortAtlasCore

/// Optional registry schemas, isolated from public IOPS source status. No privileged access.
public enum PowerTelemetry {
    public static func sample() -> PowerSample {
        sample(smc: SMCInputReader())
    }
    static func sample(smc: SMCInputReader, connectors: [HardwareConnector] = []) -> PowerSample {
        let date = Date(), status = PowerDiscovery.status()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var values: [String: Any] = [:]
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let properties, let dictionary = properties.takeRetainedValue() as NSDictionary as? [String: Any] {
                values = dictionary
            }
        }
        let connected = PowerDiscovery.status(overriding: status, battery: values).externalPower == true
        return parse(values, status: status, at: date, smc: connected ? smc.read() : nil, connectors: connectors, smcOutputs: smc.readOutputs())
    }
    static func parse(_ values: [String: Any], status: MacPowerStatus, at date: Date, smc: SMCInputReader.Reading? = nil, connectors: [HardwareConnector] = [], smcOutputs: [SMCInputReader.PortReading] = []) -> PowerSample {
        let status = PowerDiscovery.status(overriding: status, battery: values)
        let data = values["PowerTelemetryData"] as? [String: Any] ?? [:]
        func number(_ dictionary: [String: Any], _ key: String, range: ClosedRange<Double>) -> Double? {
            guard let n = dictionary[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let value = n.doubleValue
            return value.isFinite && range.contains(value) ? value : nil
        }
        func reading(_ key: String, unit: PowerMeasurement.Unit, range: ClosedRange<Double>) -> PowerMeasurement? {
            guard status.externalPower == true, let value = number(data, key, range: range) else { return nil }
            return PowerMeasurement(value: value / 1000, unit: unit, scope: .macInput,
                source: "AppleSmartBattery.PowerTelemetryData." + key, sampledAt: date)
        }
        var input = reading("SystemPowerIn", unit: .watts, range: 0...500_000)
        var voltage = reading("SystemVoltageIn", unit: .volts, range: 4000...60000)
        var current = reading("SystemCurrentIn", unit: .amps, range: 0...20000)
        if status.externalPower == true, let smc {
            input = PowerMeasurement(value: smc.watts, unit: .watts, scope: .macInput, source: smc.source, sampledAt: date)
            // Do not combine readings from different update clocks.
            voltage = smc.volts.flatMap { PowerMeasurement(value: $0, unit: .volts, scope: .macInput, source: "AppleSMC.VD0R", sampledAt: date) }
            current = smc.amps.flatMap { PowerMeasurement(value: $0, unit: .amps, scope: .macInput, source: "AppleSMC.ID0R", sampledAt: date) }
        }
        var battery: PowerMeasurement?
        // NSNumber may encode negative current as uint64 two's complement.
        if let mv = number(values, "Voltage", range: 1000...30000),
           let raw = values["InstantAmperage"] as? NSNumber ?? values["Amperage"] as? NSNumber,
           CFGetTypeID(raw) != CFBooleanGetTypeID() {
            let ma = raw.int64Value
            if (-20000...20000).contains(ma) {
                battery = PowerMeasurement(value: mv * Double(ma) / 1_000_000, unit: .watts, scope: .battery,
                    source: "AppleSmartBattery battery voltage × current", sampledAt: date)
            }
        }
        let percent = number(values, "CurrentCapacity", range: 0...100).map(Int.init)
        let name = (values["AdapterDetails"] as? [String: Any])?["Description"] as? String
        return PowerSample(sampledAt: date, status: status, input: input, inputVoltage: voltage, inputCurrent: current,
            battery: battery, batteryPercent: percent, fullyCharged: (values["FullyCharged"] as? NSNumber)?.boolValue,
            adapterName: status.externalPower == true ? name : nil,
            outputs: PowerOutputDiscovery.resolve(values["PowerOutDetails"] as? [[String: Any]] ?? [], smc: smcOutputs, connectors: connectors, at: date))
    }
}

/// One read-only SMC connection per visible sampling session.
public final class PowerSampler: @unchecked Sendable {
    private let smc = SMCInputReader()
    public init() {}
    public func sample(connectors: [HardwareConnector] = []) -> PowerSample { PowerTelemetry.sample(smc: smc, connectors: connectors) }
    public func close() { smc.close() }
}
