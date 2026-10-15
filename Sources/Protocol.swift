import AppKit

/// An 8-bit sRGB colour as the keyboard expects it.
struct RGB: Equatable, Codable {
    var r: UInt8, g: UInt8, b: UInt8

    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// Components in 0...255; out-of-range values are clamped.
    init(_ r: Double, _ g: Double, _ b: Double) {
        func clamp(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        self.init(r: clamp(r), g: clamp(g), b: clamp(b))
    }

    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF))
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    func scaled(_ f: Double) -> RGB { RGB(Double(r) * f, Double(g) * f, Double(b) * f) }
}

/// One colour per key: `Razer.rows` rows of `Razer.cols` colours.
typealias Grid = [[RGB]]

/// Razer's 90-byte report protocol for the Ornata V2, as documented by the openrazer
/// Linux driver (razerkbd_driver.c / razerchromacommon.c).
enum Razer {
    static let rows = 6
    static let cols = 22

    private static let transactionID: UInt8 = 0x1F
    private static let varStore: UInt8 = 0x01      // save in the keyboard so it survives replugging
    private static let backlightLED: UInt8 = 0x05

    static func report(_ commandClass: UInt8, _ commandID: UInt8, _ args: [UInt8], dataSize: UInt8? = nil) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 90)
        r[1] = transactionID
        r[5] = dataSize ?? UInt8(args.count)
        r[6] = commandClass
        r[7] = commandID
        for (i, a) in args.enumerated() { r[8 + i] = a }
        r[88] = r[2..<88].reduce(0, ^)
        return r
    }

    /// Class 0x0F cmd 0x02: [storage, led, effect, ...]
    private static func effect(_ id: UInt8, _ extra: [UInt8]) -> [UInt8] {
        report(0x0F, 0x02, [varStore, backlightLED, id] + extra)
    }

    static func solid(_ c: RGB) -> [[UInt8]] { [effect(0x01, [0, 0, 1, c.r, c.g, c.b])] }
    static func breathingRandom() -> [[UInt8]] { [effect(0x02, [0, 0, 0])] }
    static func breathing(_ c: RGB) -> [[UInt8]] { [effect(0x02, [1, 0, 1, c.r, c.g, c.b])] }
    static func breathing(_ a: RGB, _ b: RGB) -> [[UInt8]] { [effect(0x02, [2, 0, 2, a.r, a.g, a.b, b.r, b.g, b.b])] }
    static func spectrum() -> [[UInt8]] { [effect(0x03, [0, 0, 0])] }
    /// The wave's speed byte is a delay: 0x28 is normal, lower is faster.
    static func wave(leftward: Bool, speed: Double = 1) -> [[UInt8]] {
        let delay = UInt8(max(0x08, min(0xA0, (40 / speed).rounded())))
        return [effect(0x04, [leftward ? 2 : 1, delay, 0])]
    }
    /// Keys light up when pressed and fade; speed 1 (fast fade) ... 4 (slow).
    static func reactive(_ c: RGB, speed: UInt8) -> [[UInt8]] { [effect(0x05, [0, max(1, min(4, speed)), 1, c.r, c.g, c.b])] }
    static func off() -> [[UInt8]] { [effect(0x00, [0, 0, 0])] }

    static func brightness(_ percent: Double) -> [[UInt8]] {
        [report(0x0F, 0x04, [varStore, backlightLED, UInt8((max(0, min(100, percent)) * 2.55).rounded())])]
    }

    /// Per-key colours: one packet per row, then switch to "custom frame" so they show.
    /// Not stored in the keyboard, which is what we want for animation frames.
    static func frame(_ grid: Grid) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        for (row, colours) in grid.enumerated() {
            var args: [UInt8] = [0, 0, UInt8(row), 0, UInt8(cols - 1)]
            for c in colours { args += [c.r, c.g, c.b] }
            packets.append(report(0x0F, 0x03, args, dataSize: 0x47))
        }
        packets.append(report(0x0F, 0x02, [0, 0, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
        return packets
    }

    static func gradient(_ a: RGB, _ b: RGB) -> [[UInt8]] {
        let row = (0..<cols).map { c -> RGB in
            let t = Double(c) / Double(cols - 1)
            return RGB(Double(a.r) + (Double(b.r) - Double(a.r)) * t,
                       Double(a.g) + (Double(b.g) - Double(a.g)) * t,
                       Double(a.b) + (Double(b.b) - Double(a.b)) * t)
        }
        return frame(Array(repeating: row, count: rows))
    }
}
