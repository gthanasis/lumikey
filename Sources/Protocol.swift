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

/// One colour per key, row by row.
typealias Grid = [[RGB]]

/// Razer's 90-byte report protocol for the Ornata V2 and the keyboards in `Keyboard.all`,
/// as documented by the openrazer Linux driver (razerkbd_driver.c / razerchromacommon.c).
enum Razer {
    /// The grid the animations draw on: the Ornata V2's. Frames are resized to fit other keyboards.
    static let rows = 6
    static let cols = 22

    static let transactionID: UInt8 = 0x1F
    private static let varStore: UInt8 = 0x01      // save in the keyboard so it survives replugging
    private static let backlightLED: UInt8 = 0x05

    static func report(_ commandClass: UInt8, _ commandID: UInt8, _ args: [UInt8], dataSize: UInt8? = nil,
                       transactionID: UInt8 = transactionID) -> [UInt8] {
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
    static func frame(_ grid: Grid, for keyboard: Keyboard) -> [[UInt8]] {
        let grid = resized(grid, rows: keyboard.rows, cols: keyboard.cols)
        var packets: [[UInt8]] = []
        for (row, colours) in grid.enumerated() {
            var args: [UInt8] = [0, 0, UInt8(row), 0, UInt8(keyboard.cols - 1)]
            for c in colours { args += [c.r, c.g, c.b] }
            packets.append(report(0x0F, 0x03, args, dataSize: UInt8(5 + 3 * keyboard.cols)))
        }
        packets.append(report(0x0F, 0x02, [0, 0, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
        return packets
    }

    /// Scales a grid to another size; each new cell is the average of the cells it covers.
    static func resized(_ grid: Grid, rows: Int, cols: Int) -> Grid {
        let srcRows = grid.count, srcCols = grid.first?.count ?? 0
        if srcRows == rows && srcCols == cols { return grid }
        guard srcRows > 0, srcCols > 0 else { return Array(repeating: Array(repeating: .black, count: cols), count: rows) }
        func span(_ i: Int, _ n: Int, _ src: Int) -> Range<Int> {
            let lo = i * src / n
            return lo..<max(lo + 1, ((i + 1) * src + n - 1) / n)
        }
        return (0..<rows).map { r in
            (0..<cols).map { c in
                var sum = (0.0, 0.0, 0.0), count = 0.0
                for y in span(r, rows, srcRows) {
                    for x in span(c, cols, srcCols) {
                        let p = grid[y][x]
                        sum.0 += Double(p.r); sum.1 += Double(p.g); sum.2 += Double(p.b)
                        count += 1
                    }
                }
                return RGB(sum.0 / count, sum.1 / count, sum.2 / count)
            }
        }
    }

    /// Class 0x00 cmd 0x81: the keyboard answers with its firmware version in the first two
    /// arguments. openrazer asks every keyboard this with transaction ID 0xFF.
    static func firmwareQuery() -> [UInt8] { report(0x00, 0x81, [], dataSize: 0x02, transactionID: 0xFF) }

    /// Status 0x02 means the keyboard understood the command. The answer echoes the command,
    /// which tells it apart from the answer to something else sent at the same time.
    static func answers(_ response: [UInt8], _ request: [UInt8]) -> Bool {
        response.count == 90 && response[0] == 0x02 && response[6] == request[6] && response[7] == request[7]
    }

    static func gradient(_ a: RGB, _ b: RGB, for keyboard: Keyboard) -> [[UInt8]] {
        let row = (0..<cols).map { c -> RGB in
            let t = Double(c) / Double(cols - 1)
            return RGB(Double(a.r) + (Double(b.r) - Double(a.r)) * t,
                       Double(a.g) + (Double(b.g) - Double(a.g)) * t,
                       Double(a.b) + (Double(b.b) - Double(a.b)) * t)
        }
        return frame(Array(repeating: row, count: rows), for: keyboard)
    }
}
