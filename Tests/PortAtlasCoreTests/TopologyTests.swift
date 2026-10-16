import Testing
import Foundation
@testable import PortAtlasCore

struct TopologyTests {
    @Test func testOrphanRemainsVisibleWhenParentDisconnects() {
        let device = HardwareNode(id: "ssd", name: "SSD", kind: .device, parentID: "removed-hub")
        let snapshot = TopologySnapshot(nodes: [device], modelIdentifier: "TestMac")
        #expect(snapshot.roots.map(\.id) == ["ssd"])
        #expect(snapshot.ancestry(of: "ssd").map(\.id) == ["ssd"])
        #expect(snapshot.rootPort(for: "ssd") == nil)
    }
    @Test func testCycleCannotHangPathReconstruction() {
        let a = HardwareNode(id: "a", name: "A", kind: .hub, parentID: "b")
        let b = HardwareNode(id: "b", name: "B", kind: .hub, parentID: "a")
        let snapshot = TopologySnapshot(nodes: [a, b], modelIdentifier: "TestMac")
        #expect(Set(snapshot.ancestry(of: "a").map(\.id)) == ["a", "b"])
    }
    @Test func testHostEnumerationDoesNotUseLegacySpeedNumbers() {
        #expect(LinkSpeed.hostEnumeration(0) == nil)
        #expect(LinkSpeed.hostEnumeration(1)?.megabitsPerSecond == 12)
        #expect(LinkSpeed.hostEnumeration(2)?.megabitsPerSecond == 1.5)
        #expect(LinkSpeed.hostEnumeration(3)?.megabitsPerSecond == 480)
        #expect(LinkSpeed.hostEnumeration(4)?.megabitsPerSecond == 5000)
        #expect(LinkSpeed.hostEnumeration(6)?.megabitsPerSecond == 20000)
        #expect(LinkSpeed.hostEnumeration(7) == nil)
        #expect(LinkSpeed.hostEnumeration(999) == nil)
    }
    @Test func testUSBDeviceUsesRootPortBeyondItsHub() {
        let snapshot = TopologySnapshot.demo
        #expect(snapshot.rootPort(for: "demo-ssd")?.id == "demo-port")
        #expect(snapshot.ancestry(of: "demo-ssd").map(\.id) == ["demo-controller", "demo-port", "demo-hub", "demo-ssd"])
    }
}
