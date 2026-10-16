import Foundation
import DiskArbitration
import IOKit
import PortAtlasCore

/// Metadata only: no files opened, no names or capacities persisted.
enum StorageDiscovery {
    static func volumes(deviceIDs: Set<String>) -> [StorageVolume] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let media = DADiskCopyIOMedia(disk) as io_service_t?, media != 0 else { return nil }
            defer { IOObjectRelease(media) }
            // Never infer ownership from a volume name, bus number, or disk numbering.
            guard let deviceID = storageAncestor(media, deviceIDs: deviceIDs), deviceIDs.contains(deviceID),
                  let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
            return StorageVolume(id: url.path, deviceID: deviceID, name: values.volumeName ?? "Mounted volume",
                                 totalBytes: Int64(total), availableBytes: Int64(available))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func storageAncestor(_ media: io_registry_entry_t, deviceIDs: Set<String>) -> String? {
        var current = media
        IOObjectRetain(current)
        var visited: Set<UInt64> = []
        while current != 0 {
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(current, &id) == KERN_SUCCESS, visited.insert(id).inserted else {
                IOObjectRelease(current); return nil
            }
            if deviceIDs.contains(String(id)) {
                IOObjectRelease(current); return String(id)
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard result == KERN_SUCCESS else { return nil }
            current = parent
        }
        return nil
    }
}
