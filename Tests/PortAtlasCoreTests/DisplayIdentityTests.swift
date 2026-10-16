import Foundation
import Testing
@testable import PortAtlasCore

struct DisplayIdentityTests {
    @Test func acceptsValidIdentityAndRejectsDamagedEDID() {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes.replaceSubrange(0..<8, with: [0,255,255,255,255,255,255,0])
        bytes[8] = 0x12; bytes[9] = 0x34
        bytes[10] = 0x78; bytes[11] = 0x56
        bytes[12] = 1; bytes[15] = 2
        bytes[127] = UInt8((256 - bytes.reduce(0) { $0 + Int($1) } % 256) % 256)
        let identity = DisplayIdentity(edid: Data(bytes))
        #expect(identity?.vendor == 0x1234)
        #expect(identity?.product == 0x5678)
        #expect(identity?.serial == 0x02000001)
        bytes[20] = 1
        #expect(DisplayIdentity(edid: Data(bytes)) == nil)
        #expect(DisplayIdentity(edid: Data(bytes.prefix(64))) == nil)
    }
}
