import Foundation
import Testing
import PortAtlasCore
import PortAtlasHardware

struct DisplaySignalTests {
    private var fixture: [String: Any] {
        ["NormalModeActive": true, "external": true, "DPTimingModeId": 53,
         "DisplayAttributes": ["NativeFormatHorizontalPixels": 3840, "NativeFormatVerticalPixels": 2160,
                               "ProductAttributes": ["LegacyManufacturerID": 12462, "ProductID": 26563, "SerialNumber": 0]],
         "TimingElements": [
            ["ID": 53, "IsVirtual": false, "IsInterlaced": false, "IsSplit": false,
             "HorizontalAttributes": ["Active": 3840, "Total": 4000, "PreciseSyncRate": 8736768],
             "VerticalAttributes": ["Active": 2160, "PreciseSyncRate": 3931939]],
            ["ID": 84, "IsVirtual": false, "IsInterlaced": false,
             "HorizontalAttributes": ["Active": 2560], "VerticalAttributes": ["Active": 1440, "PreciseSyncRate": 3932160]]]]
    }
    @Test func scaledDesktopKeepsActualOutputTiming() throws {
        let report = try #require(DisplayDiscovery.decode(fixture))
        let display = DisplayDevice(id: 1, name: "Fixture", width: 2560, height: 1440, signal: report.signal)
        #expect(display.width == 2560)
        #expect(display.signal?.resolution.width == 3840)
        #expect(display.signal?.resolution.height == 2160)
        #expect(abs(report.signal.refreshRate - 60) < 0.01)
        #expect(display.mapLabel == "3840 × 2160 · 60 Hz")
        #expect(report.signal.pixelClockHz == 533250000)
    }
    @Test func vrrRangeBelongsToSelectedTimingNotGeneralDisplayCapability() throws {
        var values = fixture
        var attributes = values["DisplayAttributes"] as! [String: Any]
        attributes["MinimumVariableRefreshRate"] = 40 * 65536
        attributes["MaximumVariableRefreshRate"] = 120 * 65536
        values["DisplayAttributes"] = attributes
        #expect(DisplayDiscovery.decode(values)?.signal.variableRefreshRange == nil)
        var timings = values["TimingElements"] as! [[String: Any]]
        timings[0]["MinimumVariableRefreshRate"] = 40 * 65536
        timings[0]["MaximumVariableRefreshRate"] = 120 * 65536
        values["TimingElements"] = timings
        #expect(DisplayDiscovery.decode(values)?.signal.variableRefreshRange?.minimum == 40)
        values["DPTimingModeId"] = 84
        #expect(DisplayDiscovery.decode(values)?.signal.variableRefreshRange == nil)
    }
    @Test func nativeCapabilityCannotReplaceMissingCurrentTiming() {
        var values = fixture; values.removeValue(forKey: "DPTimingModeId")
        #expect(DisplayDiscovery.decode(values) == nil)
        let unknown = DisplayDevice(id: 1, name: "Fixture", width: 2560, height: 1440, nativeResolution: DisplayResolution(width: 3840, height: 2160))
        #expect(unknown.mapLabel == "Signal resolution unavailable")
    }
    @Test func inactiveVirtualAmbiguousAndInvalidSchemasStayUnknown() {
        var inactive = fixture; inactive["NormalModeActive"] = false
        #expect(DisplayDiscovery.decode(inactive) == nil)
        var unknown = fixture; unknown["DPTimingModeId"] = 999
        #expect(DisplayDiscovery.decode(unknown) == nil)
        var timings = fixture["TimingElements"] as! [[String: Any]]
        var virtual = fixture; timings[0]["IsVirtual"] = true; virtual["TimingElements"] = timings
        #expect(DisplayDiscovery.decode(virtual) == nil)
        timings = fixture["TimingElements"] as! [[String: Any]]
        var duplicate = fixture; duplicate["TimingElements"] = [timings[0], timings[0]]
        #expect(DisplayDiscovery.decode(duplicate) == nil)
        timings[0]["HorizontalAttributes"] = ["Active": true]
        var malformed = fixture; malformed["TimingElements"] = timings
        #expect(DisplayDiscovery.decode(malformed) == nil)
    }
    @Test func selectedLowerResolutionIsNotPromotedToNative4K() throws {
        var values = fixture; values["DPTimingModeId"] = 84
        let report = try #require(DisplayDiscovery.decode(values))
        #expect(report.signal.resolution.width == 2560)
        #expect(report.nativeResolution?.width == 3840)
    }
    @Test func bandwidthUsesEncodingAndLaneCountWithoutClaimingUsage() throws {
        let full = try #require(DisplayDiscovery.decodeLink(["LinkRateDescription": "8.1 Gbps (HBR3)", "LaneCount": 4]))
        #expect(full.rawGigabits == 32.4)
        #expect(abs(full.payloadGigabits - 25.92) < 0.001)
        #expect(full.payloadLabel == "25.92 Gb/s")
        #expect(DisplayDiscovery.decodeLink(["LinkRateDescription": "5.4 Gbps (HBR2)", "LaneCount": 2])?.payloadLabel == "8.64 Gb/s")
        #expect(DisplayDiscovery.decodeLink(["LinkRateDescription": "UHBR20", "LaneCount": 4]) == nil)
        #expect(DisplayDiscovery.decodeLink(["LinkRateDescription": "8.1 Gbps (HBR3)", "LaneCount": 3]) == nil)
    }
}
