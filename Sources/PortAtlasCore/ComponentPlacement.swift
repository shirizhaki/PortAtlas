import Foundation
import CryptoKit

public enum ComponentPlacement: String, Codable, CaseIterable, Sendable {
    case automatic, grouped, separate
    public var label: String {
        switch self { case .automatic: return "Automatic"; case .grouped: return "Dock component"; case .separate: return "Separate accessory" }
    }
}

/// Local physical-view preferences; registry IDs and hardware topology stay untouched.
public struct ComponentPlacementPreferences: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var choices: [String: ComponentPlacement] = [:]
    public init() {}
    public func key(for node: HardwareNode, in snapshot: TopologySnapshot) -> String? {
        guard !node.registryPath.isEmpty,
              snapshot.nodes.filter({ $0.registryPath == node.registryPath }).count == 1 else { return nil }
        // Hash the connection path and identity rather than storing device names or paths.
        // Reconnecting at another physical USB route intentionally requires a new choice.
        let parts = [snapshot.modelIdentifier, node.registryPath, node.kind.rawValue, node.name,
                     node.vendorID.map(String.init) ?? "", node.productID.map(String.init) ?? "", node.transport ?? ""]
        guard let data = try? JSONEncoder().encode(parts) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func placement(for node: HardwareNode, in snapshot: TopologySnapshot) -> ComponentPlacement {
        key(for: node, in: snapshot).flatMap { choices[$0] } ?? .automatic
    }
    public mutating func set(_ placement: ComponentPlacement, for node: HardwareNode, in snapshot: TopologySnapshot) {
        guard let key = key(for: node, in: snapshot) else { return }
        if placement == .automatic { choices.removeValue(forKey: key) } else { choices[key] = placement }
    }
}

public struct ComponentPlacementStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: ComponentPlacementStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(url: folder.appendingPathComponent("PortAtlas/presentation.json"))
    }
    public func load() throws -> ComponentPlacementPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return ComponentPlacementPreferences() }
        let prefs = try JSONDecoder().decode(ComponentPlacementPreferences.self, from: Data(contentsOf: url))
        guard prefs.schemaVersion == 1, prefs.choices.count <= 500,
              prefs.choices.keys.allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) else { throw ConfigurationError.invalidData }
        return prefs
    }
    public func save(_ preferences: ComponentPlacementPreferences) throws {
        guard preferences.choices.count <= 500 else { throw ConfigurationError.invalidData }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}
