import Foundation

/// Measured power sourced by a Mac connector, not a downstream device's battery state.
public struct PortPowerOutput: Equatable, Sendable {
    public let connectorID: String
    public let watts: Double
    public let volts: Double
    public let amps: Double
    public let configuredWatts: Double?
    public let source: String
    public let sampledAt: Date
    public init?(connectorID: String, watts: Double, volts: Double, amps: Double,
                 configuredWatts: Double? = nil, source: String, sampledAt: Date) {
        guard !connectorID.isEmpty, watts.isFinite, (0.01...100).contains(watts),
              volts.isFinite, (4...30).contains(volts), amps.isFinite, (0.001...10).contains(amps) else { return nil }
        self.connectorID = connectorID; self.watts = watts; self.volts = volts; self.amps = amps
        self.configuredWatts = configuredWatts.flatMap { $0.isFinite && (0.01...100).contains($0) ? $0 : nil }
        self.source = source; self.sampledAt = sampledAt
    }
    /// Only fresh, uniquely scoped readings contribute; missing output is not zero.
    public static func measuredTotal(_ readings: [PortPowerOutput], at now: Date) -> Double? {
        let unique = Dictionary(grouping: readings.filter { $0.isFresh(at: now) }, by: \.connectorID)
            .values.compactMap { $0.count == 1 ? $0.first : nil }
        return unique.isEmpty ? nil : unique.reduce(0) { $0 + $1.watts }
    }
    public var label: String { String(format: "%.1f W", watts) }
    public func isFresh(at now: Date) -> Bool { (-1...5).contains(now.timeIntervalSince(sampledAt)) }
}
