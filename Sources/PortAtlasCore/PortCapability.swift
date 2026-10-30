import Foundation

public enum PortCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, usb2, usb3_5, usb3_10, usb3_20, usb4, thunderbolt3, thunderbolt4, thunderbolt5
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unknown: return "Capability unknown"
        case .usb2: return "USB 2 · 480 Mb/s"
        case .usb3_5: return "USB 3 · 5 Gb/s"
        case .usb3_10: return "USB 3 · 10 Gb/s"
        case .usb3_20: return "USB 3 · 20 Gb/s"
        case .usb4: return "USB4"
        case .thunderbolt3: return "Thunderbolt 3"
        case .thunderbolt4: return "Thunderbolt 4 · USB4"
        case .thunderbolt5: return "Thunderbolt 5 · USB4"
        }
    }
}

/// Only uniform USB-C capabilities are automatic. Mixed-port machines require per-socket
/// evidence or manual configuration. A connector's negotiated USB speed proves no TB support.
public struct MacCapabilityProfile: Sendable {
    public let capability: PortCapability
    public let sourceURL: URL
    public static func verified(for model: String) -> Self? {
        // Apple lists these identifiers and their Thunderbolt generation explicitly:
        // https://support.apple.com/en-us/108052 (verified October 2026).
        let tb4: Set<String> = ["Mac16,1", "Mac17,2", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11"]
        let tb5: Set<String> = ["Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9"]
        guard tb4.contains(model) || tb5.contains(model) else { return nil }
        return Self(capability: tb4.contains(model) ? .thunderbolt4 : .thunderbolt5,
                    sourceURL: URL(string: "https://support.apple.com/en-us/108052")!)
    }
}

public enum MacFormFactor: String, Sendable { case laptop, desktop }

/// Which Mac this is, for its illustration and name. Read from the product name macOS
/// reports (for example "MacBook Air (13-inch, M2, 2022)"); this is not a model table.
public enum MacProduct: String, CaseIterable, Sendable {
    case macBook, macMini, macStudio, iMac, macPro, desktop
    public init(productName: String?, hasBattery: Bool) {
        let name = productName?.lowercased() ?? ""
        // "iMac Pro" contains "mac pro", so iMac is checked first.
        if name.hasPrefix("macbook") { self = .macBook }
        else if name.hasPrefix("imac") { self = .iMac }
        else if name.hasPrefix("mac mini") { self = .macMini }
        else if name.hasPrefix("mac studio") { self = .macStudio }
        else if name.hasPrefix("mac pro") { self = .macPro }
        else { self = hasBattery ? .macBook : .desktop }
    }
    public var formFactor: MacFormFactor { self == .macBook ? .laptop : .desktop }
    public var symbol: String {
        switch self {
        case .macBook: return "laptopcomputer"
        case .macMini: return "macmini"
        case .macStudio: return "macstudio"
        case .iMac, .desktop: return "desktopcomputer"
        case .macPro: return "macpro.gen3"
        }
    }
}
