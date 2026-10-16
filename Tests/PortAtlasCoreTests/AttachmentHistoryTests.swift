import Foundation
import Testing
import PortAtlasCore

struct AttachmentHistoryTests {
    private let hub = HardwareNode(id: "hub", name: "Hub", kind: .hub)
    private let child = HardwareNode(id: "adapter", name: "Adapter", kind: .device, parentID: "hub")
    private func snapshot(_ nodes: [HardwareNode], _ seconds: Double) -> TopologySnapshot {
        TopologySnapshot(nodes: nodes, modelIdentifier: "Fixture", capturedAt: Date(timeIntervalSince1970: seconds))
    }
    @Test func initialAndStaggeredEnumerationRemainGrouped() {
        var history = AttachmentHistory()
        history.observe(snapshot([hub], 0))
        history.observe(snapshot([hub, child], 0.5))
        history.observe(snapshot([hub, child], 10))
        #expect(history.laterAttachments.isEmpty)
    }
    @Test func laterDeviceStaysSeparateUntilDisconnect() {
        var history = AttachmentHistory()
        history.observe(snapshot([hub], 0))
        history.observe(snapshot([hub, child], 5))
        #expect(history.laterAttachments == [child.id])
        history.observe(snapshot([hub, child], 10))
        #expect(history.laterAttachments == [child.id])
        history.observe(snapshot([], 12))
        #expect(history.laterAttachments.isEmpty)
        history.observe(snapshot([hub, child], 15))
        #expect(history.laterAttachments.isEmpty)
    }
    @Test func newHubSubtreeDoesNotSplitEveryInitialChild() {
        var history = AttachmentHistory()
        let nested = HardwareNode(id: "nested", name: "Nested", kind: .hub, parentID: hub.id)
        let device = HardwareNode(id: "keyboard", name: "Keyboard", kind: .device, parentID: nested.id)
        history.observe(snapshot([hub], 0))
        history.observe(snapshot([hub, nested, device], 5))
        #expect(history.laterAttachments == [nested.id])
    }
}
