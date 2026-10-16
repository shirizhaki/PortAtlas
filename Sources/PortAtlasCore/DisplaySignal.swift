import Foundation

public struct DisplayResolution: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public init?(width: Int, height: Int) {
        guard (1...32768).contains(width), (1...32768).contains(height) else { return nil }
        self.width = width; self.height = height
    }
    public var label: String { "\(width) × \(height)" }
}

/// Output timing selected by the display controller, independent of desktop scaling.
public struct DisplaySignal: Equatable, Sendable {
    public let resolution: DisplayResolution
    public let refreshRate: Double
    public let pixelClockHz: Double?
    public let variableRefreshRange: DisplayRefreshRange?
    public init?(resolution: DisplayResolution, refreshRate: Double, pixelClockHz: Double? = nil, variableRefreshRange: DisplayRefreshRange? = nil) {
        guard refreshRate.isFinite, (1...1000).contains(refreshRate) else { return nil }
        self.resolution = resolution; self.refreshRate = refreshRate
        self.variableRefreshRange = variableRefreshRange
        self.pixelClockHz = pixelClockHz.flatMap { $0.isFinite && (1...10_000_000_000).contains($0) ? $0 : nil }
    }
    public var label: String {
        if let range = variableRefreshRange { return resolution.label + " · VRR " + range.label }
        return resolution.label + String(format: " · %g Hz", (refreshRate * 100).rounded() / 100) }
}

/// Capacity of the active DP link. This is not video usage or a Thunderbolt reservation.
public struct DisplayLinkCapacity: Equatable, Sendable {
    public let gigabitsPerLane: Double
    public let lanes: Int
    public init?(gigabitsPerLane: Double, lanes: Int) {
        guard [1.62, 2.7, 5.4, 8.1].contains(gigabitsPerLane), [1, 2, 4].contains(lanes) else { return nil }
        self.gigabitsPerLane = gigabitsPerLane; self.lanes = lanes
    }
    public var rawGigabits: Double { gigabitsPerLane * Double(lanes) }
    public var payloadGigabits: Double { rawGigabits * 0.8 }
    public var payloadLabel: String { String(format: "%g Gb/s", (payloadGigabits * 100).rounded() / 100) }
    public var rawLabel: String { String(format: "%g Gb/s", rawGigabits) }
}
