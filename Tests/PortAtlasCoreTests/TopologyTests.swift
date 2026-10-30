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

struct ThunderboltBranchTests {
    private let mac = [
        HardwareNode(id: "controller", name: "Controller", kind: .controller),
        HardwareNode(id: "usb3", name: "Logical port 1", kind: .port, parentID: "controller", registryPath: "mac://usb3", connectorPath: "mac://right-1", transport: "USB 3 branch"),
        HardwareNode(id: "usb2", name: "Logical port 2", kind: .port, parentID: "controller", registryPath: "mac://usb2", connectorPath: "mac://right-1", transport: "USB 2 branch")
    ]
    @Test func dockRouterStartsFromTheMacControllerOfItsConnector() {
        let dock = HardwareNode(id: "dock", name: "Dock", kind: .hub, parentID: "host-root-router", connectorPath: "mac://right-1", transport: "Thunderbolt router")
        let dockController = HardwareNode(id: "dock-controller", name: "Dock xHCI", kind: .controller, parentID: "dock")
        let snapshot = TopologySnapshot(nodes: ThunderboltBranches.attach(mac + [dock, dockController]), modelIdentifier: "TestMac")
        #expect(snapshot.roots.map(\.id) == ["controller"])
        #expect(snapshot.ancestry(of: "dock-controller").map(\.id) == ["controller", "thunderbolt-branch:mac://right-1", "dock", "dock-controller"])
        // The new branch shares the connector, so the dock still belongs to that one physical socket.
        #expect(snapshot.connectorPath(for: "dock-controller") == "mac://right-1")
        #expect(snapshot.accessoryRoots.map(\.id) == ["dock"])
    }
    @Test func routerWithoutAMatchingMacBranchIsLeftAlone() {
        let dock = HardwareNode(id: "dock", name: "Dock", kind: .hub, connectorPath: "mac://left-1", transport: "Thunderbolt router")
        let nodes = ThunderboltBranches.attach(mac + [dock])
        #expect(nodes.count == mac.count + 1)
        #expect(nodes.last?.parentID == nil)
    }
    @Test func daisyChainedRouterKeepsItsUpstreamRouter() {
        let first = HardwareNode(id: "first", name: "Dock", kind: .hub, connectorPath: "mac://right-1", transport: "Thunderbolt router")
        let second = HardwareNode(id: "second", name: "Display", kind: .hub, parentID: "first", connectorPath: "mac://right-1", transport: "Thunderbolt router")
        let nodes = ThunderboltBranches.attach(mac + [first, second])
        #expect(nodes.first { $0.id == "second" }?.parentID == "first")
        #expect(nodes.filter { $0.kind == .port && $0.transport == ThunderboltBranches.transport }.count == 1)
    }
}
