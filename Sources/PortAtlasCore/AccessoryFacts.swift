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
    public var label: String {
        if isActive == false { return "Ethernet · no link" }
        guard isActive == true, let bitsPerSecond else { return "Ethernet · speed not reported" }
        return bitsPerSecond >= 1_000_000_000 ? String(format: "Ethernet · %g Gb/s", bitsPerSecond / 1_000_000_000)
            : String(format: "Ethernet · %g Mb/s", bitsPerSecond / 1_000_000)
    }
}
