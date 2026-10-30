import Foundation

public struct CableIdentity: Equatable, Sendable {
    public let productType: String
    public let pdRevision: Int?
    public init(productType: String, pdRevision: Int? = nil) {
        self.productType = productType; self.pdRevision = pdRevision
    }
}
public struct NetworkLink: Identifiable, Equatable, Sendable {
    public let id: String
    public let deviceID: String
    public let isActive: Bool?
    public let bitsPerSecond: Double?
    public let sampledAt: Date
    public init(id: String, deviceID: String, isActive: Bool?, bitsPerSecond: Double?, sampledAt: Date) {
        self.id = id; self.deviceID = deviceID; self.isActive = isActive
        self.bitsPerSecond = bitsPerSecond; self.sampledAt = sampledAt
    }
    /// A physical Ethernet port reports a link speed once a cable is in, or that no cable is in.
    /// Virtual interfaces, such as the ones an iPhone exposes over USB for Personal Hotspot and
    /// syncing, report an active link with no speed, and are not shown as Ethernet.
    public var isPhysicalPort: Bool { isActive == false || (isActive == true && bitsPerSecond != nil) }
    public var label: String {
        if isActive == false { return "No cable" }
        guard isActive == true, let bitsPerSecond else { return "Connected" }
        return bitsPerSecond >= 1_000_000_000 ? String(format: "%g Gb/s", bitsPerSecond / 1_000_000_000)
            : String(format: "%g Mb/s", bitsPerSecond / 1_000_000)
    }
}
