import Foundation

public enum ConnectorKind: String, Sendable {
    case usbC, usbA, magSafe, hdmi
    public static func detected(portType: String, builtIn: Bool?, appleSilicon: Bool) -> Self? {
        if portType == "USB-C" { return .usbC }
        // A dock's downstream socket must never become a physical socket on the Mac.
        if portType == "USB-A", builtIn == true { return .usbA }
        if portType == "HDMI", appleSilicon { return .hdmi }
        if portType.hasPrefix("MagSafe"), appleSilicon { return .magSafe }
        return nil
    }
}

/// Contract limits, never measured consumption. Advertised options are kept separate.
public struct ConnectorPower: Equatable, Sendable {
    public let contractWatts: Int?
    public let voltageMillivolts: Int?
    public let currentMilliamps: Int?
    public let advertisedWatts: Int?
    public init(contractWatts: Int? = nil, voltageMillivolts: Int? = nil, currentMilliamps: Int? = nil, advertisedWatts: Int? = nil) {
        self.contractWatts = contractWatts; self.voltageMillivolts = voltageMillivolts
        self.currentMilliamps = currentMilliamps; self.advertisedWatts = advertisedWatts
    }
}

public struct PowerRoute: Equatable, Sendable {
    public enum Evidence: String, Sendable { case reportedContract, onlyConnectedInput }
    public let connectorID: String
    public let evidence: Evidence
    public var label: String { evidence == .reportedContract ? "Input route inferred from the only reported PD contract" : "Input route inferred · only connected power input" }
}

public enum PowerRouting {
    public static func resolve(connectors: [HardwareConnector], externalPower: Bool?) -> PowerRoute? {
        guard externalPower == true else { return nil }
        let candidates = connectors.filter { ($0.kind == .usbC || $0.kind == .magSafe) && $0.connectionActive != false && $0.powerContractWatts != nil }
        if candidates.count == 1 { return PowerRoute(connectorID: candidates[0].id, evidence: .reportedContract) }
        guard candidates.isEmpty else { return nil }
        // A MagSafe cable can be attached while USB-C supplies power. Without a
        // selected contract, infer only when *all* USB-C sockets report inactive.
        let magSafe = connectors.filter { $0.kind == .magSafe && $0.connectionActive == true }
        let usbC = connectors.filter { $0.kind == .usbC }
        guard magSafe.count == 1, !usbC.isEmpty, usbC.allSatisfy({ $0.connectionActive == false }) else { return nil }
        return PowerRoute(connectorID: magSafe[0].id, evidence: .onlyConnectedInput)
    }
}
