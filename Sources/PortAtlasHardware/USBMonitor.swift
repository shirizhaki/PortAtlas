import Foundation
import IOKit
import IOKit.ps

/// Owned on the main queue. Notifications are coalesced; there is no polling timer.
public final class USBMonitor {
    private var powerSource: CFRunLoopSource?
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var settling: DispatchWorkItem?
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void
    public init(onChange: @escaping () -> Void) { self.onChange = onChange }

    public func start() throws {
        guard port == nil else { return }
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else {
            throw DiscoveryError.registry("USB notifications", kIOReturnNoResources)
        }
        port = notificationPort
        IONotificationPortSetDispatchQueue(notificationPort, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue().signal()
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        do {
            for className in ["IOUSBHostDevice", "AppleUSBHostPort", "AppleUSBHostController", "IOPortTransportState", "IOThunderboltSwitch"] {
                for event in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                    var iterator: io_iterator_t = 0
                    let status = IOServiceAddMatchingNotification(notificationPort, event,
                        IOServiceMatching(className), { context, iterator in
                            drain(iterator)
                            guard let context else { return }
                            Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue().signal()
                        }, context, &iterator)
                    guard status == KERN_SUCCESS else { throw DiscoveryError.registry("USB notifications", status) }
                    iterators.append(iterator)
                    drain(iterator) // Exhausting each iterator arms its notifications.
                }
            }
        } catch { stop(); throw error }
    }
    public func stop() {
        pending?.cancel(); pending = nil
        settling?.cancel(); settling = nil
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }; powerSource = nil
        iterators.forEach { IOObjectRelease($0) }; iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }; port = nil
    }
    private func signal() {
        pending?.cancel()
        settling?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        // PD / transport properties can settle after the entry is published.
        // One bounded follow-up read per event, not continuous polling.
        let settled = DispatchWorkItem { [weak self] in self?.onChange() }
        settling = settled; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: settled)
    }
    deinit { stop() }
}

private func drain(_ iterator: io_iterator_t) {
    while case let entry = IOIteratorNext(iterator), entry != 0 { IOObjectRelease(entry) }
}
