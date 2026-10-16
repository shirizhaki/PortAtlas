import Foundation

/// Read-only transport state attached to an actual IOPort. It does not identify a display
/// or invent the intermediate devices between that port and its endpoints.
public struct PortTransportLink: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case displayPort, hdmi, thunderboltUSB4, usb3 }
    public let id: String
    public let kind: Kind
    public let detail: String?
    public let registryPath: String
    public init(id: String, kind: Kind, detail: String? = nil, registryPath: String) {
        self.id = id; self.kind = kind; self.detail = detail; self.registryPath = registryPath
    }
    public var isDisplay: Bool { kind == .displayPort || kind == .hdmi }
    public var label: String { kind == .hdmi ? "HDMI link active" : kind == .displayPort ? "DisplayPort link active" : kind == .usb3 ? "USB 3 link active" : "Thunderbolt / USB4 link active" }
    public var symbol: String { isDisplay ? "display" : "bolt.horizontal" }
}

public struct ThunderboltDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String?
    public let registryPath: String
    public init(id: String, name: String, parentID: String?, registryPath: String) {
        self.id = id; self.name = name; self.parentID = parentID; self.registryPath = registryPath
    }
}

public struct MacPowerStatus: Equatable, Sendable {
    public let externalPower: Bool?
    public let isCharging: Bool?
    /// Reported adapter rating, never instantaneous consumption.
    public let adapterWatts: Int?
    public init(externalPower: Bool? = nil, isCharging: Bool? = nil, adapterWatts: Int? = nil) {
        self.externalPower = externalPower; self.isCharging = isCharging
        self.adapterWatts = adapterWatts.flatMap { $0 > 0 ? $0 : nil }
    }
    public var label: String {
        if externalPower == false { return "On battery" }
        guard externalPower == true else { return "Power source unavailable" }
        return isCharging == true ? "Charging" : "External power connected"
    }
}

public struct DisplayDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let width: Int
    public let height: Int
    public let refreshRate: Double?
    public let signal: DisplaySignal?
    public let nativeResolution: DisplayResolution?
    public let renderedResolution: DisplayResolution?
    public let linkCapacity: DisplayLinkCapacity?
    public let edid: DisplayEDID?
    public let availableModes: [DisplayModeSummary]
    public var mapLabel: String { signal?.label ?? "Signal resolution unavailable" }
    public init(id: UInt32, name: String, width: Int, height: Int, refreshRate: Double? = nil,
                signal: DisplaySignal? = nil, nativeResolution: DisplayResolution? = nil,
                renderedResolution: DisplayResolution? = nil, linkCapacity: DisplayLinkCapacity? = nil,
                edid: DisplayEDID? = nil, availableModes: [DisplayModeSummary] = []) {
        self.id = id; self.name = name; self.width = width; self.height = height
        self.refreshRate = refreshRate.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        self.signal = signal; self.nativeResolution = nativeResolution
        self.renderedResolution = renderedResolution; self.linkCapacity = linkCapacity
        self.edid = edid; self.availableModes = availableModes
    }
}
