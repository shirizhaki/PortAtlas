import Foundation
import IOKit
import PortAtlasCore

/// Read-only DC-input rails adapted from WhatPort SMCPowerReader (MIT, Darryl
/// Morley; e672756). UUID-matched output rails share this read-only connection; no write command or privileged helper.
/// The connection and key cache are protected by the lock.
final class SMCInputReader: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var keyInfo: [UInt32: SMCKeyInfoData] = [:]

    struct Reading: Equatable, Sendable {
        let watts: Double
        let volts: Double?
        let amps: Double?
        let source: String
    }

    deinit { close() }
    func close() {
        lock.lock(); defer { lock.unlock() }
        closeLocked()
    }
    private func closeLocked() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        keyInfo.removeAll()
    }
    func read() -> Reading? {
        lock.lock(); defer { lock.unlock() }
        guard openLocked() else { return nil }
        return Self.decode(readKey: { self.readFloat($0) })
    }

    private func openLocked() -> Bool {
        guard MemoryLayout<SMCParamStruct>.stride == 80 else { return false }
        if connection == 0 {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != 0 else { return false }
            defer { IOObjectRelease(service) }
            guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { connection = 0; return false }
        }
        return true
    }
    struct PortReading: Equatable, Sendable {
        let uuid: String
        let volts: Double
        let amps: Double
        var watts: Double { volts * amps }
    }
    func readOutputs() -> [PortReading] {
        lock.lock(); defer { lock.unlock() }
        guard openLocked() else { return [] }
        // Read only existing keys. D-channel indices are never physical port numbers.
        return (1...8).compactMap { index in
            guard let bytes = readBytes("D\(index)UI", type: "hex_", size: 16),
                  let uuid = Self.decodeUUID(bytes),
                  let volts = readFloat("D\(index)JV"), let amps = readFloat("D\(index)JI") else { return nil }
            return Self.decodeOutput(uuid: uuid, volts: volts, amps: amps)
        }
    }
    static func decodeUUID(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 16, bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func decodeOutput(uuid: String, volts: Double, amps: Double) -> PortReading? {
        guard PowerOutputDiscovery.normalizedUUID(uuid) != nil,
              volts.isFinite, (4...30).contains(volts), amps.isFinite, (0...10).contains(amps), volts * amps <= 100 else { return nil }
        return PortReading(uuid: uuid, volts: volts, amps: amps)
    }

    /// Missing/zero rails during negotiation must not manufacture an input reading.
    static func decode(readKey: (String) -> Double?) -> Reading? {
        func valid(_ key: String, _ range: ClosedRange<Double>) -> Double? {
            guard let value = readKey(key), value.isFinite, range.contains(value) else { return nil }
            return value
        }
        let volts = valid("VD0R", 4...60)
        let amps = valid("ID0R", 0...20)
        if let watts = valid("PDTR", 0.001...500) {
            return Reading(watts: watts, volts: volts, amps: amps, source: "AppleSMC.PDTR")
        }
        guard let volts, let amps, amps > 0, volts * amps <= 500 else { return nil }
        return Reading(watts: volts * amps, volts: volts, amps: amps, source: "AppleSMC.VD0R × ID0R")
    }
    static func decodeFloat(_ bytes: [UInt8]) -> Double? {
        guard bytes.count == 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }
    static func fourCC(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private func readFloat(_ key: String) -> Double? {
        readBytes(key, type: "flt ", size: 4).flatMap(Self.decodeFloat)
    }
    private func readBytes(_ key: String, type: String, size: UInt32) -> [UInt8]? {
        guard let code = Self.fourCC(key) else { return nil }
        let info: SMCKeyInfoData
        if let cached = keyInfo[code] { info = cached }
        else {
            var request = SMCParamStruct(); request.key = code; request.data8 = 9
            guard let response = call(&request) else { return nil }
            info = response.keyInfo
            guard info.dataSize == size, info.dataType == Self.fourCC(type) else { return nil }
            keyInfo[code] = info
        }
        guard info.dataSize == size, info.dataType == Self.fourCC(type) else { return nil }
        var request = SMCParamStruct(); request.key = code; request.keyInfo = info; request.data8 = 5
        guard let response = call(&request) else { return nil }
        var bytes = response.bytes
        return withUnsafeBytes(of: &bytes) { Array($0.prefix(Int(size))) }
    }
    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var output = SMCParamStruct(), size = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &size)
        guard result == KERN_SUCCESS else { closeLocked(); return nil }
        guard size == MemoryLayout<SMCParamStruct>.stride, output.result == 0 else { return nil }
        return output
    }
}

// The 80-byte kernel ABI retains the C padding before result/status.
private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    // C keeps keyInfo's 3-byte trailing padding before `result`; Swift would
    // otherwise pack `result` into it and shrink the struct to 76 bytes, which
    // the kernel rejects. This explicit pad restores the C offsets (total 80).
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
