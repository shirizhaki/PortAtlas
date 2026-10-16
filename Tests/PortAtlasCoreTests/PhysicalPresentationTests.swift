import Testing
@testable import PortAtlasCore

struct PhysicalPresentationTests {
    let router = HardwareNode(id: "r", name: "Unfamiliar brand", kind: .hub, transport: "USB4 router")
    func drive(_ id: String, parent: String = "r") -> HardwareNode {
        HardwareNode(id: id, name: "Different SSD brand", kind: .device, parentID: parent,
                     interfaceClasses: [8], transport: "PCIe / NVMe storage")
    }
    func presentation(_ nodes: [HardwareNode]) -> PhysicalPresentation {
        PhysicalPresentation(snapshot: TopologySnapshot(nodes: nodes, modelIdentifier: "OtherMac"))
    }
    @Test func combinesOnlyOneDirectNVMeDriveWithoutChangingLogicalGraph() {
        let view = presentation([router, drive("ssd")])
        #expect(view.combinedStorage(for: router)?.id == "ssd")
        #expect(view.combinedStorageIDs == ["ssd"])
        #expect(view.snapshot.children(of: "r").map(\.id) == ["ssd"])
        #expect(view.snapshot.nodes.count == 2)
    }
    @Test func multipleDrivesAndOtherFunctionsPreventCombination() {
        #expect(presentation([router, drive("a"), drive("b")]).combinedStorage(for: router) == nil)
        let usb = HardwareNode(id: "usb", name: "Controller", kind: .controller, parentID: "r")
        #expect(presentation([router, drive("a"), usb]).combinedStorage(for: router) == nil)
    }
    @Test func missingOrIndirectEvidenceDoesNotCombine() {
        let port = HardwareNode(id: "port", name: "Port", kind: .port, parentID: "r")
        #expect(presentation([router, port, drive("a", parent: "port")]).combinedStorage(for: router) == nil)
        let ordinaryHub = HardwareNode(id: "r", name: "Looks like a storage enclosure", kind: .hub)
        #expect(presentation([ordinaryHub, drive("a")]).combinedStorage(for: ordinaryHub) == nil)
        #expect(presentation([router]).combinedStorage(for: router) == nil)
    }
}
