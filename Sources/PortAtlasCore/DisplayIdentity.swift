import Foundation

/// Transient EDID identity used only to correlate a live display with a reported route.
public struct DisplayIdentity: Equatable, Sendable {
    public let vendor: UInt32
    public let product: UInt32
    public let serial: UInt32
    public init?(edid: Data) {
        let b = Array(edid)
        guard b.count >= 128, Array(b.prefix(8)) == [0,255,255,255,255,255,255,0],
              b.prefix(128).reduce(0, { $0 + Int($1) }) % 256 == 0 else { return nil }
        vendor = UInt32(b[8]) << 8 | UInt32(b[9])
        product = UInt32(b[10]) | UInt32(b[11]) << 8
        serial = (0..<4).reduce(0) { $0 | UInt32(b[12 + $1]) << (8 * $1) }
    }
}
