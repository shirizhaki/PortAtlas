import Foundation

/// A reported variable timing range, never an instantaneous refresh measurement.
public struct DisplayRefreshRange: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public init?(minimum: Double, maximum: Double) {
        guard minimum.isFinite, maximum.isFinite, minimum >= 1, maximum <= 1000, minimum < maximum else { return nil }
        self.minimum = minimum; self.maximum = maximum
    }
    public var label: String { String(format: "%g–%g Hz", (minimum * 100).rounded() / 100, (maximum * 100).rounded() / 100) }
}

/// A selectable macOS desktop mode. Pixel size may describe a scaled render buffer.
public struct DisplayModeSummary: Equatable, Hashable, Sendable, Identifiable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double?
    public var id: Self { self }
    public init?(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        guard DisplayResolution(width: width, height: height) != nil,
              DisplayResolution(width: pixelWidth, height: pixelHeight) != nil,
              refreshRate.isFinite, refreshRate >= 0, refreshRate <= 1000 else { return nil }
        self.width = width; self.height = height; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate > 0 ? (refreshRate * 100).rounded() / 100 : nil
    }
    public var label: String {
        "\(width) × \(height) · " + (refreshRate.map { String(format: "%g Hz", $0) } ?? "Rate unspecified")
    }
    public var renderLabel: String? { width != pixelWidth || height != pixelHeight ? "Renders at \(pixelWidth) × \(pixelHeight)" : nil }
}

/// Validated live EDID. Kept in memory; never saved as a hardware profile.
public struct DisplayEDID: Equatable, Sendable {
    public let data: Data
    public let manufacturer: String
    public let product: UInt32
    public let serial: UInt32
    public let name: String?
    public let serialText: String?
    public let version: String
    public let manufactureYear: Int
    public let detailedTimings: [DisplaySignal]
    public var hex: String { data.map { String(format: "%02X", $0) }.joined() }
    public init?(data: Data) {
        let b = Array(data)
        guard let identity = DisplayIdentity(edid: data), b.count <= 4096 else { return nil }
        let count = (Int(b[126]) + 1) * 128
        guard count <= b.count, count <= 4096 else { return nil }
        for offset in stride(from: 0, to: count, by: 128) {
            guard b[offset..<(offset + 128)].reduce(0, { $0 + Int($1) }) % 256 == 0 else { return nil }
        }
        let letters = [10,5,0].map { Int((identity.vendor >> $0) & 31) }
        guard letters.allSatisfy({ (1...26).contains($0) }) else { return nil }
        manufacturer = String(letters.map { Character(UnicodeScalar($0 + 64)!) })
        self.data = data.prefix(count); product = identity.product; serial = identity.serial
        version = "\(b[18]).\(b[19])"; manufactureYear = 1990 + Int(b[17])
        var displayName: String?, textSerial: String?, timings: [DisplaySignal] = []
        func descriptor(_ offset: Int) {
            if b[offset] == 0 && b[offset + 1] == 0 {
                guard b[offset + 2] == 0, b[offset + 4] == 0,
                      let text = String(bytes: b[(offset + 5)..<(offset + 18)], encoding: .ascii) else { return }
                let clean = text.components(separatedBy: "\n")[0].trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                if !clean.isEmpty {
                    if b[offset + 3] == 0xfc { displayName = clean }
                    if b[offset + 3] == 0xff { textSerial = clean }
                }
                return
            }
            let clock = (Int(b[offset]) | Int(b[offset + 1]) << 8) * 10000
            let width = Int(b[offset + 2]) | Int(b[offset + 4] & 0xf0) << 4
            let blankWidth = Int(b[offset + 3]) | Int(b[offset + 4] & 0x0f) << 8
            let height = Int(b[offset + 5]) | Int(b[offset + 7] & 0xf0) << 4
            let blankHeight = Int(b[offset + 6]) | Int(b[offset + 7] & 0x0f) << 8
            // Interlaced detailed timings need field/frame interpretation; omit them.
            guard b[offset + 17] & 0x80 == 0, clock > 0, blankWidth > 0, blankHeight > 0,
                  let resolution = DisplayResolution(width: width, height: height),
                  let signal = DisplaySignal(resolution: resolution, refreshRate: Double(clock) / Double((width + blankWidth) * (height + blankHeight)), pixelClockHz: Double(clock)) else { return }
            if !timings.contains(signal) { timings.append(signal) }
        }
        for offset in stride(from: 54, through: 108, by: 18) { descriptor(offset) }
        for block in stride(from: 128, to: count, by: 128) where b[block] == 0x02 {
            let start = Int(b[block + 2])
            guard (4...109).contains(start) else { continue }
            for offset in stride(from: block + start, through: block + 109, by: 18) { descriptor(offset) }
        }
        name = displayName; serialText = textSerial; detailedTimings = timings
    }
}
