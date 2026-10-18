import Foundation

/// A Razer keyboard the app knows how to drive. Every one listed here uses the same
/// commands as the Ornata V2 (same report layout, transaction ID 0x1F, backlight LED 0x05)
/// according to the openrazer driver; they differ only in product ID, the USB interface
/// the reports go to, and the size of the LED grid.
struct Keyboard: Identifiable, Equatable {
    let name: String
    let productID: UInt16
    let interface: UInt16
    let rows: Int
    let cols: Int
    /// Checked on a real keyboard. The rest are expected to work but nobody has tried yet.
    let verified: Bool

    var id: UInt16 { productID }
    var usbID: String { String(format: "1532:%04X", productID) }

    /// Fewer than a handful of rows means lighting zones rather than one LED per key.
    var hasPerKeyLighting: Bool { rows > 1 }

    static let all: [Keyboard] = [
        .init(name: "Razer Ornata V2", productID: 0x025D, interface: 2, rows: 6, cols: 22, verified: true),
        .init(name: "Razer Ornata V3", productID: 0x02A1, interface: 2, rows: 1, cols: 10, verified: false),
        .init(name: "Razer Ornata V3", productID: 0x028F, interface: 2, rows: 1, cols: 10, verified: false),
        .init(name: "Razer Ornata V3 Tenkeyless", productID: 0x02A3, interface: 2, rows: 1, cols: 8, verified: false),
        .init(name: "Razer Cynosa V2", productID: 0x025E, interface: 1, rows: 6, cols: 22, verified: false),
        .init(name: "Razer BlackWidow Elite", productID: 0x0228, interface: 1, rows: 6, cols: 22, verified: false),
        .init(name: "Razer BlackWidow V3 Mini HyperSpeed (wired)", productID: 0x0258, interface: 3, rows: 5, cols: 16, verified: false),
        .init(name: "Razer BlackWidow V4", productID: 0x0287, interface: 3, rows: 8, cols: 23, verified: false),
        .init(name: "Razer BlackWidow V4 Pro", productID: 0x028D, interface: 3, rows: 8, cols: 23, verified: false),
        .init(name: "Razer BlackWidow V4 75%", productID: 0x02A5, interface: 3, rows: 6, cols: 16, verified: false),
        .init(name: "Razer BlackWidow V4 Tenkeyless HyperSpeed (wired)", productID: 0x02D7, interface: 3, rows: 6, cols: 18, verified: false),
        .init(name: "Razer BlackWidow V4 Mini HyperSpeed (wired)", productID: 0x02B9, interface: 3, rows: 5, cols: 14, verified: false),
        .init(name: "Razer Huntsman V2", productID: 0x026C, interface: 3, rows: 6, cols: 22, verified: false),
        .init(name: "Razer Huntsman V2 Tenkeyless", productID: 0x026B, interface: 3, rows: 6, cols: 18, verified: false),
        .init(name: "Razer Huntsman V2 Analog", productID: 0x0266, interface: 3, rows: 8, cols: 22, verified: false),
        .init(name: "Razer Huntsman Mini Analog", productID: 0x0282, interface: 3, rows: 5, cols: 15, verified: false),
        .init(name: "Razer Huntsman V3 Pro", productID: 0x02A6, interface: 3, rows: 6, cols: 22, verified: false),
        .init(name: "Razer Huntsman V3 Pro Tenkeyless", productID: 0x02A7, interface: 3, rows: 6, cols: 22, verified: false),
        .init(name: "Razer Huntsman V3 Pro Mini", productID: 0x02B0, interface: 3, rows: 5, cols: 15, verified: false),
        .init(name: "Razer Joro", productID: 0x02CD, interface: 3, rows: 6, cols: 16, verified: false),
    ]

    static func known(_ productID: UInt16) -> Keyboard? { all.first { $0.productID == productID } }

    /// Sends a report and returns the keyboard's answer to it, or nil if there isn't one.
    /// Blocking; call off the main thread.
    func ask(_ report: [UInt8]) -> [UInt8]? {
        for _ in 0..<3 {
            var response = [UInt8](repeating: 0, count: Int(RAZER_REPORT_LEN))
            let sent = report.withUnsafeBufferPointer { razer_query(productID, interface, $0.baseAddress, &response) }
            if sent == 0 && Razer.answers(response, report) { return response }
            usleep(20_000)
        }
        return nil
    }

    /// The firmware version, e.g. "v1.1", if the keyboard answers.
    func firmware() -> String? {
        ask(Razer.firmwareQuery()).map { "v\($0[8]).\($0[9])" }
    }
}

/// A connected Razer USB device: a keyboard from the list above, or something else
/// (a mouse, a headset, or a keyboard the app doesn't know yet).
struct RazerDevice: Equatable {
    let productID: UInt16
    let name: String

    var keyboard: Keyboard? { Keyboard.known(productID) }
    var usbID: String { String(format: "1532:%04X", productID) }

    static func connected() -> [RazerDevice] {
        var ids = [UInt16](repeating: 0, count: 16)
        let count = min(Int(razer_list(&ids, Int32(ids.count))), ids.count)
        var seen = Set<UInt16>()
        return ids.prefix(count).filter { seen.insert($0).inserted }.map { id in
            var buffer = [CChar](repeating: 0, count: 128)
            let name = razer_product_name(id, &buffer, Int32(buffer.count)) != 0
                ? String(cString: buffer) : "Razer device"
            return RazerDevice(productID: id, name: Keyboard.known(id)?.name ?? name)
        }
    }
}

/// Which keyboard the app can drive right now, if any.
enum Detection: Equatable {
    /// No Razer devices at all.
    case none
    case ready(Keyboard)
    /// A known keyboard that hasn't been tested, and untested keyboards are switched off.
    case untested(Keyboard)
    /// Razer devices, but none the app knows.
    case unsupported([RazerDevice])

    var keyboard: Keyboard? {
        if case .ready(let k) = self { return k }
        return nil
    }

    static func detect(allowUntested: Bool) -> Detection {
        let devices = RazerDevice.connected()
        let keyboards = devices.compactMap(\.keyboard)
        if let k = keyboards.first(where: \.verified) { return .ready(k) }
        if let k = keyboards.first { return allowUntested ? .ready(k) : .untested(k) }
        return devices.isEmpty ? .none : .unsupported(devices)
    }
}
