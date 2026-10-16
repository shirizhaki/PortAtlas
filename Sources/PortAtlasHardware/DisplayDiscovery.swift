import Foundation
import IOKit
import CoreGraphics
import PortAtlasCore

/// Optional Apple Silicon registry schemas stay here. No model table, display control,
/// private framework, EDID-native-as-current assumption, or positional display matching.
public enum DisplayDiscovery {
    public struct Report: Equatable, Sendable {
        public let vendor: UInt32
        public let product: UInt32
        public let serial: UInt32
        public let signal: DisplaySignal
        public let nativeResolution: DisplayResolution?
    }

    public static func signals() -> [UInt32: Report] {
        let displays = externalDisplays()
        var reports: [Report] = []
        var seen = Set<UInt64>()
        for name in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            enumerate(name) { entry in
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                      seen.insert(id).inserted, let report = decode(properties(entry)) else { return }
                reports.append(report)
            }
        }
        var matches: [UInt32: [Report]] = [:]
        for report in reports {
            let ids = displays.filter {
                CGDisplayVendorNumber($0) == report.vendor && CGDisplayModelNumber($0) == report.product && CGDisplaySerialNumber($0) == report.serial
            }
            guard ids.count == 1, let id = ids.first else { continue }
            matches[id, default: []].append(report)
        }
        return matches.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    public static func linkCapacities() -> [UInt32: DisplayLinkCapacity] {
        let displays = externalDisplays()
        var matches: [UInt32: [DisplayLinkCapacity]] = [:]
        enumerate("IOPortTransportStateDisplayPort") { entry in
            let values = properties(entry)
            guard values["ParentBuiltInPortTypeDescription"] as? String != "HDMI",
                  (values["Active"] as? NSNumber)?.boolValue == true,
                  integer(values["SinkCount"]) == 1,
                  let edid = values["EDID"] as? Data, let identity = DisplayIdentity(edid: edid),
                  let capacity = decodeLink(values) else { return }
            let ids = displays.filter { CGDisplayVendorNumber($0) == identity.vendor && CGDisplayModelNumber($0) == identity.product && CGDisplaySerialNumber($0) == identity.serial }
            guard ids.count == 1, let id = ids.first else { return }
            matches[id, default: []].append(capacity)
        }
        return matches.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    public static func decode(_ values: [String: Any]) -> Report? {
        guard (values["NormalModeActive"] as? NSNumber)?.boolValue == true,
              (values["external"] as? NSNumber)?.boolValue == true,
              let attributes = values["DisplayAttributes"] as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any],
              let vendor = integer(product["LegacyManufacturerID"]), (1...65535).contains(vendor),
              let model = integer(product["ProductID"]), (0...65535).contains(model),
              let serial = integer(product["SerialNumber"]), serial >= 0, UInt64(serial) <= UInt32.max,
              let mode = integer(values["DPTimingModeId"]),
              let timings = values["TimingElements"] as? [[String: Any]] else { return nil }
        let selected = timings.filter { integer($0["ID"]) == mode }
        guard selected.count == 1, let timing = selected.first,
              (timing["IsVirtual"] as? NSNumber)?.boolValue == false,
              (timing["IsInterlaced"] as? NSNumber)?.boolValue == false,
              (timing["IsSplit"] as? NSNumber)?.boolValue != true,
              let horizontal = timing["HorizontalAttributes"] as? [String: Any],
              let vertical = timing["VerticalAttributes"] as? [String: Any],
              let width = integer(horizontal["Active"]), let height = integer(vertical["Active"]),
              let resolution = DisplayResolution(width: width, height: height),
              let fixedRate = integer(vertical["PreciseSyncRate"]), fixedRate > 0 else { return nil }
        // TimingElements stores vertical Hz and horizontal kHz as 16.16 fixed point.
        let clock: Double?
        if let horizontalRate = integer(horizontal["PreciseSyncRate"]), let total = integer(horizontal["Total"]),
           horizontalRate > 0, total >= width, total <= 65536 {
            clock = Double(horizontalRate) / 65536 * 1000 * Double(total)
        } else { clock = nil }
        guard let signal = DisplaySignal(resolution: resolution, refreshRate: Double(fixedRate) / 65536, pixelClockHz: clock, variableRefreshRange: decodeRefreshRange(timing)) else { return nil }
        let native: DisplayResolution?
        if let w = integer(attributes["NativeFormatHorizontalPixels"]), let h = integer(attributes["NativeFormatVerticalPixels"]) {
            native = DisplayResolution(width: w, height: h)
        } else { native = nil }
        return Report(vendor: UInt32(vendor), product: UInt32(model), serial: UInt32(serial), signal: signal, nativeResolution: native)
    }

    public static func decodeRefreshRange(_ timing: [String: Any]) -> DisplayRefreshRange? {
        guard let minimum = integer(timing["MinimumVariableRefreshRate"]),
              let maximum = integer(timing["MaximumVariableRefreshRate"]) else { return nil }
        return DisplayRefreshRange(minimum: Double(minimum) / 65536, maximum: Double(maximum) / 65536)
    }

    public static func edids() -> [UInt32: DisplayEDID] {
        let displays = externalDisplays()
        var matches: [UInt32: [DisplayEDID]] = [:]
        enumerate("IOPortTransportStateDisplayPort") { entry in
            let values = properties(entry)
            guard (values["Active"] as? NSNumber)?.boolValue == true,
                  integer(values["SinkCount"]) == 1,
                  let data = values["EDID"] as? Data, let identity = DisplayIdentity(edid: data),
                  let edid = DisplayEDID(data: data) else { return }
            let ids = displays.filter { CGDisplayVendorNumber($0) == identity.vendor && CGDisplayModelNumber($0) == identity.product && CGDisplaySerialNumber($0) == identity.serial }
            guard ids.count == 1, let id = ids.first else { return }
            matches[id, default: []].append(edid)
        }
        return matches.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    public static func availableModes(for display: UInt32) -> [DisplayModeSummary] {
        guard let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] else { return [] }
        let summaries = modes.filter { $0.isUsableForDesktopGUI() }.compactMap {
            DisplayModeSummary(width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, refreshRate: $0.refreshRate)
        }
        return Set(summaries).sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            if $0.pixelHeight != $1.pixelHeight { return $0.pixelHeight > $1.pixelHeight }
            return ($0.refreshRate ?? 0) > ($1.refreshRate ?? 0)
        }
    }

    public static func decodeLink(_ values: [String: Any]) -> DisplayLinkCapacity? {
        guard let description = values["LinkRateDescription"] as? String,
              let lanes = integer(values["LaneCount"]) else { return nil }
        // Only known reported schemas; unknown/UHBR encoding must not use the HBR formula.
        let rates: [String: Double] = ["1.62 Gbps (RBR)": 1.62, "2.7 Gbps (HBR)": 2.7, "5.4 Gbps (HBR2)": 5.4, "8.1 Gbps (HBR3)": 8.1]
        guard let rate = rates[description] else { return nil }
        return DisplayLinkCapacity(gigabitsPerLane: rate, lanes: lanes)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }
    private static func externalDisplays() -> [UInt32] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }
    private static func enumerate(_ name: String, visit: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 { visit(entry); IOObjectRelease(entry) }
    }
    private static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
        var values: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &values, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return values?.takeRetainedValue() as? [String: Any] ?? [:]
    }
}
