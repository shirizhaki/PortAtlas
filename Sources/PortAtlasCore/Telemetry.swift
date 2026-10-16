import Foundation

/// A system reading with scope, units and freshness. Missing readings are never zero.
public struct PowerMeasurement: Equatable, Sendable {
    public enum Unit: String, Sendable { case watts = "W", volts = "V", amps = "A" }
    public enum Scope: String, Sendable { case macInput, battery }
    public let value: Double
    public let unit: Unit
    public let scope: Scope
    public let source: String
    public let sampledAt: Date
    public init?(value: Double, unit: Unit, scope: Scope, source: String, sampledAt: Date) {
        guard value.isFinite else { return nil }
        self.value = value; self.unit = unit; self.scope = scope
        self.source = source; self.sampledAt = sampledAt
    }
    public func isFresh(at now: Date, maximumAge: TimeInterval = 5) -> Bool {
        let age = now.timeIntervalSince(sampledAt)
        return age >= -1 && age <= maximumAge
    }
    public var label: String { String(format: "%.1f %@", value, unit.rawValue) }
}

public struct PowerSample: Equatable, Sendable {
    public let sampledAt: Date
    public let status: MacPowerStatus
    public let input: PowerMeasurement?
    public let inputVoltage: PowerMeasurement?
    public let inputCurrent: PowerMeasurement?
    /// Positive means charging; negative means discharging. Derived from battery V × I.
    public let battery: PowerMeasurement?
    public let batteryPercent: Int?
    public let fullyCharged: Bool?
    public let adapterName: String?
    public let outputs: [PortPowerOutput]
    public init(sampledAt: Date = Date(), status: MacPowerStatus = MacPowerStatus(), input: PowerMeasurement? = nil,
                inputVoltage: PowerMeasurement? = nil, inputCurrent: PowerMeasurement? = nil, battery: PowerMeasurement? = nil,
                batteryPercent: Int? = nil, fullyCharged: Bool? = nil, adapterName: String? = nil, outputs: [PortPowerOutput] = []) {
        self.sampledAt = sampledAt; self.status = status; self.input = input
        self.inputVoltage = inputVoltage; self.inputCurrent = inputCurrent; self.battery = battery
        self.batteryPercent = batteryPercent; self.fullyCharged = fullyCharged; self.adapterName = adapterName; self.outputs = outputs
    }
    public func liveInput(at now: Date) -> PowerMeasurement? {
        guard status.externalPower == true, let input, input.scope == .macInput, input.unit == .watts, input.value >= 0, input.isFresh(at: now) else { return nil }
        return input
    }
    public var chargingLabel: String {
        if status.externalPower == false { return "On battery" }
        if status.isCharging == true { return "Charging" }
        if status.externalPower == true { return fullyCharged == true ? "Fully charged" : "Connected · not charging" }
        return "Power source unavailable"
    }
}

/// Session-only history; gaps and source changes cannot become continuous graph segments.
public struct PowerHistory: Sendable {
    public private(set) var samples: [PowerSample] = []
    public init() {}
    public mutating func append(_ sample: PowerSample) {
        if let last = samples.last, last.status.externalPower != sample.status.externalPower { samples.removeAll() }
        samples.removeAll { sample.sampledAt.timeIntervalSince($0.sampledAt) > 60 }
        samples.append(sample)
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }
    public mutating func reset() { samples.removeAll() }
}
