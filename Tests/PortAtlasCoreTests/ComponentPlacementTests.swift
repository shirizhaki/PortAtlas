import Foundation
import Testing
import PortAtlasCore

struct ComponentPlacementTests {
    let dock = HardwareNode(id: "dock", name: "Fixture dock", kind: .hub, registryPath: "fixture://dock", transport: "Thunderbolt router")
    func component(id: String = "receiver", name: String = "Fixture receiver", classes: [Int] = [3], path: String = "fixture://dock/usb/2") -> HardwareNode {
        HardwareNode(id: id, name: name, kind: .device, parentID: "dock", registryPath: path, vendorID: 1, productID: 2, interfaceClasses: classes)
    }
    func snapshot(_ node: HardwareNode) -> TopologySnapshot { TopologySnapshot(nodes: [dock, node], modelIdentifier: "FixtureMac") }
    @Test func manualGroupingOverridesRecognitionTimingWithoutChangingLogicalAncestry() {
        let receiver = component(), source = snapshot(component())
        var prefs = ComponentPlacementPreferences(); prefs.set(.grouped, for: receiver, in: source)
        let grouped = PhysicalPresentation(snapshot: source, preferences: prefs)
        #expect(grouped.shouldSeparate(receiver, automatically: true) == false)
        #expect(grouped.snapshot.node(receiver.id)?.parentID == dock.id)
        prefs.set(.separate, for: receiver, in: source)
        #expect(PhysicalPresentation(snapshot: source, preferences: prefs).shouldSeparate(receiver, automatically: false))
        prefs.set(.automatic, for: receiver, in: source)
        #expect(prefs.choices.isEmpty)
        #expect(PhysicalPresentation(snapshot: source, preferences: prefs).shouldSeparate(receiver, automatically: false) == false)
    }
    @Test func choiceSurvivesReenumerationButDoesNotLeakToAnotherConnection() {
        let original = component(), source = snapshot(component())
        var prefs = ComponentPlacementPreferences(); prefs.set(.separate, for: original, in: source)
        let reconnected = component(id: "new-entry")
        #expect(prefs.placement(for: reconnected, in: snapshot(reconnected)) == .separate)
        let moved = component(path: "fixture://different-dock/usb/2")
        #expect(prefs.placement(for: moved, in: snapshot(moved)) == .automatic)
        #expect(prefs.key(for: original, in: TopologySnapshot(nodes: [original, reconnected], modelIdentifier: "FixtureMac")) == nil)
    }
    @Test func manualSeparationCanUnfoldACombinedStorageEndpoint() {
        let storage = HardwareNode(id: "ssd", name: "Fixture SSD", kind: .device, parentID: "dock", registryPath: "fixture://dock/nvme", interfaceClasses: [8], transport: "PCIe / NVMe storage")
        let source = snapshot(storage)
        #expect(PhysicalPresentation(snapshot: source).combinedStorage(for: dock)?.id == storage.id)
        var prefs = ComponentPlacementPreferences(); prefs.set(.separate, for: storage, in: source)
        #expect(PhysicalPresentation(snapshot: source, preferences: prefs).combinedStorage(for: dock) == nil)
        #expect(source.node(storage.id)?.parentID == dock.id)
    }
    @Test func localPreferencesRoundTripWithoutStoringRawDeviceNamesOrPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComponentPlacementStore(url: directory.appendingPathComponent("presentation.json"))
        let receiver = component(), source = snapshot(component())
        var prefs = ComponentPlacementPreferences(); prefs.set(.grouped, for: receiver, in: source)
        try store.save(prefs)
        #expect(try store.load() == prefs)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(!text.contains(receiver.name) && !text.contains(receiver.registryPath))
        try Data("{broken".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "{broken")
    }
}
