import Foundation
import Testing
import PortAtlasCore

struct PortCapabilityTests {
    @Test func supportedLinkRateDoesNotDependOnModelOrCurrentDevice() {
        #expect(LinkSpeed.thunderboltMaximum(speedMask: 12, width: 2)?.megabitsPerSecond == 40000)
        #expect(LinkSpeed.thunderboltMaximum(speedMask: 14, width: 2)?.megabitsPerSecond == 80000)
        #expect(LinkSpeed.thunderboltMaximum(speedMask: 8, width: 2)?.megabitsPerSecond == 20000)
        #expect(LinkSpeed.thunderboltMaximum(speedMask: 16, width: 2) == nil)
        #expect(LinkSpeed.thunderboltMaximum(speedMask: 14, width: 3) == nil)
    }
    @Test func profileNeverGuessesFromAModelFamily() {
        #expect(MacCapabilityProfile.verified(for: "Mac16,1")?.capability == .thunderbolt4)
        #expect(MacCapabilityProfile.verified(for: "Mac16,6")?.capability == .thunderbolt5)
        #expect(MacCapabilityProfile.verified(for: "Mac16,99") == nil)
        #expect(MacCapabilityProfile.verified(for: "Mac16,10") == nil) // Mixed front/rear mini ports.
        #expect(MacCapabilityProfile.verified(for: "Unknown Mac") == nil)
    }
    @Test func manualCapabilityIncludingUnknownSurvivesSaving() throws {
        var config = PortConfiguration()
        config.ports = [PhysicalPort(name: "USB 2", side: .left, capability: .usb2),
                        PhysicalPort(name: "Unknown", side: .right, capability: .unknown)]
        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(PortConfiguration.self, from: data)
        #expect(restored.ports[0].capability == .usb2)
        #expect(restored.ports[1].capability == .unknown)
    }
}
