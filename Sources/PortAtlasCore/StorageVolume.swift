import Foundation

/// Mounted filesystem space, not raw device capacity. Shared APFS volumes are never summed.
public struct StorageVolume: Identifiable, Equatable, Sendable {
    public let id: String
    public let deviceID: String
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usedBytes: Int64 { totalBytes - availableBytes }
    public var usedFraction: Double { Double(usedBytes) / Double(totalBytes) }
    public init?(id: String, deviceID: String, name: String, totalBytes: Int64, availableBytes: Int64) {
        guard totalBytes > 0, availableBytes >= 0, availableBytes <= totalBytes else { return nil }
        self.id = id; self.deviceID = deviceID; self.name = name
        self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
}
