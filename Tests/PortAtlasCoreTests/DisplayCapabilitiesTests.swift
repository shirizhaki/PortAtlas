import Foundation
import Testing
import PortAtlasCore
import PortAtlasHardware

struct DisplayCapabilitiesTests {
    private func checksum(_ bytes: inout [UInt8], block: Int = 0) {
        let start = block * 128
        bytes[start + 127] = UInt8((256 - bytes[start..<(start + 127)].reduce(0, { $0 + Int($1) }) % 256) % 256)
    }
    private var edid: [UInt8] {
        var b = [UInt8](repeating: 0, count: 128)
        b.replaceSubrange(0..<8, with: [0,255,255,255,255,255,255,0])
        b[8] = 0x1e; b[9] = 0x6d // GSM
        b[10] = 0x34; b[11] = 0x12; b[12] = 42
        b[17] = 34; b[18] = 1; b[19] = 4
        // A 1920 × 1080, 60 Hz progressive detailed timing, 148.5 MHz.
        b.replaceSubrange(54..<66, with: [0x02,0x3a,0x80,0x18,0x71,0x38,0x2d,0x40,0,0,0,0])
        b[75] = 0xfc
        b.replaceSubrange(77..<90, with: Array("Test display\n ".utf8))
        checksum(&b); return b
    }
    @Test func decodesIdentityAndTimingWithoutTurningEDIDIntoCurrentSignal() throws {
        let info = try #require(DisplayEDID(data: Data(edid)))
        #expect(info.manufacturer == "GSM")
        #expect(info.product == 0x1234 && info.serial == 42)
        #expect(info.name == "Test display")
        #expect(info.version == "1.4" && info.manufactureYear == 2024)
        let timing = try #require(info.detailedTimings.first)
        #expect(timing.resolution == DisplayResolution(width: 1920, height: 1080))
        #expect(timing.refreshRate == 60)
        #expect(info.hex.count == 256)
        #expect(DisplayDevice(id: 1, name: "Test", width: 1280, height: 720, edid: info).signal == nil)
    }
    @Test func rejectsCorruptionTruncationAndInvalidExtensionChecksum() {
        var bad = edid; bad[20] ^= 1
        #expect(DisplayEDID(data: Data(bad)) == nil)
        #expect(DisplayEDID(data: Data(edid.prefix(127))) == nil)
        bad = edid; bad[126] = 1; checksum(&bad)
        #expect(DisplayEDID(data: Data(bad)) == nil)
        bad += [UInt8](repeating: 0, count: 128); bad[128] = 2
        #expect(DisplayEDID(data: Data(bad)) == nil)
        checksum(&bad, block: 1)
        #expect(DisplayEDID(data: Data(bad)) != nil)
    }
    @Test func malformedExtensionDescriptorBoundsNeverEscapeBlock() {
        for start: UInt8 in [0,1,3,110,127,255] {
            var b = edid; b[126] = 1; checksum(&b)
            b += [UInt8](repeating: 0, count: 128); b[128] = 2; b[130] = start; checksum(&b, block: 1)
            #expect(DisplayEDID(data: Data(b))?.detailedTimings.count == 1)
        }
    }
    @Test func variableTimingUsesValidatedFixedPointRange() throws {
        let range = try #require(DisplayDiscovery.decodeRefreshRange(["MinimumVariableRefreshRate": 40 * 65536, "MaximumVariableRefreshRate": 120 * 65536]))
        #expect(range.label == "40–120 Hz")
        let signal = try #require(DisplaySignal(resolution: DisplayResolution(width: 3840, height: 2160)!, refreshRate: 120, variableRefreshRange: range))
        #expect(signal.label == "3840 × 2160 · VRR 40–120 Hz")
        #expect(signal.refreshRate == 120)
        for values: [String: Any] in [[:], ["MinimumVariableRefreshRate": true, "MaximumVariableRefreshRate": 7864320], ["MinimumVariableRefreshRate": 0, "MaximumVariableRefreshRate": 7864320], ["MinimumVariableRefreshRate": 7864320, "MaximumVariableRefreshRate": 2621440]] {
            #expect(DisplayDiscovery.decodeRefreshRange(values) == nil)
        }
    }
    @Test func desktopModesRetainScalingAndUnspecifiedRate() throws {
        let mode = try #require(DisplayModeSummary(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 0))
        #expect(mode.refreshRate == nil)
        #expect(mode.renderLabel == "Renders at 5120 × 2880")
        #expect(mode.label.contains("Rate unspecified"))
        #expect(DisplayModeSummary(width: 0, height: 1, pixelWidth: 1, pixelHeight: 1, refreshRate: 60) == nil)
        #expect(DisplayModeSummary(width: 1, height: 1, pixelWidth: 1, pixelHeight: 1, refreshRate: .nan) == nil)
    }
}
