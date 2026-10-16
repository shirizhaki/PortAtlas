import Testing
import PortAtlasCore

struct StorageVolumeTests {
    @Test func invalidCapacityIsOmittedRatherThanInventingAUsageBar() {
        for (total, free) in [(0, 0), (-1, 0), (100, -1), (100, 101)] {
            #expect(StorageVolume(id: "fixture", deviceID: "ssd", name: "Volume", totalBytes: Int64(total), availableBytes: Int64(free)) == nil)
        }
    }
    @Test func fullAndEmptyVolumesHaveValidFractions() {
        #expect(StorageVolume(id: "full", deviceID: "ssd", name: "Full", totalBytes: 100, availableBytes: 0)?.usedFraction == 1)
        #expect(StorageVolume(id: "empty", deviceID: "ssd", name: "Empty", totalBytes: 100, availableBytes: 100)?.usedFraction == 0)
        #expect(StorageVolume(id: "partial", deviceID: "ssd", name: "Partial", totalBytes: 100, availableBytes: 35)?.usedBytes == 65)
    }
}
