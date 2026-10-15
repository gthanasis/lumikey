import AppKit
import Combine

/// What the keyboard is showing. Saved so the app can put it back on next launch.
enum Mode: Codable, Equatable {
    case animation(String)
    case solid(RGB)
    case gradient(RGB, RGB)
    case breathing([RGB])
    case typing(RGB, speed: UInt8)
    case spectrum
    case wave
    case off

    var packets: [[UInt8]] {
        switch self {
        case .animation: return []
        case .solid(let c): return Razer.solid(c)
        case .gradient(let a, let b): return Razer.gradient(a, b)
        case .breathing(let cs):
            switch cs.count {
            case 0: return Razer.breathingRandom()
            case 1: return Razer.breathing(cs[0])
            default: return Razer.breathing(cs[0], cs[1])
            }
        case .typing(let c, let speed): return Razer.reactive(c, speed: speed)
        case .spectrum: return Razer.spectrum()
        case .wave: return Razer.wave(leftward: false)
        case .off: return Razer.off()
        }
    }

    var label: String {
        switch self {
        case .animation(let id): return Effects.info(id)?.name ?? id
        case .solid: return "Solid colour"
        case .gradient: return "Gradient"
        case .breathing: return "Breathing"
        case .typing: return "Lights up as you type"
        case .spectrum: return "Spectrum cycle"
        case .wave: return "Wave"
        case .off: return "Lights off"
        }
    }
}

/// Owns the keyboard. All USB traffic goes through one serial queue; animations run on
/// their own thread and push a frame roughly every 35 ms.
final class Lights: ObservableObject {
    @Published private(set) var mode: Mode?
    @Published private(set) var connected = true
    @Published var brightness: Double {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness") }
    }

    private let usb = DispatchQueue(label: "ornata.usb")
    private var animation: Thread?
    private var animationCancelled = false
    private let animationLock = NSLock()

    init() {
        brightness = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 100
        if let data = UserDefaults.standard.data(forKey: "mode"),
           let saved = try? JSONDecoder().decode(Mode.self, from: data) {
            apply(saved)
        }
    }

    var playingAnimation: String? {
        if case .animation(let id) = mode { return id }
        return nil
    }

    func apply(_ newMode: Mode) {
        stopAnimation()
        mode = newMode
        if let data = try? JSONEncoder().encode(newMode) { UserDefaults.standard.set(data, forKey: "mode") }
        if case .animation(let id) = newMode, let info = Effects.info(id) {
            startAnimation(info.make())
        } else {
            send(newMode.packets)
        }
    }

    func setBrightness(_ percent: Double) {
        brightness = percent
        send(Razer.brightness(percent))
    }

    /// Stops the animation but leaves the last frame on the keys.
    func stopAnimation() {
        animationLock.lock()
        animationCancelled = true
        animationLock.unlock()
        // Wait for the thread to finish its current frame so frames and commands don't interleave.
        while animation?.isFinished == false { usleep(2_000) }
        animation = nil
        if case .animation = mode { mode = nil }
    }

    func checkConnection() {
        let isConnected = ornata_connected() != 0
        if isConnected != connected { connected = isConnected }
    }

    private func send(_ packets: [[UInt8]]) {
        usb.async { [weak self] in
            let ok = Self.write(packets)
            DispatchQueue.main.async { self?.connected = ok }
        }
    }

    /// Blocking; call off the main thread.
    private static func write(_ packets: [[UInt8]]) -> Bool {
        for p in packets {
            let result = p.withUnsafeBufferPointer { ornata_send($0.baseAddress) }
            if result != 0 { return false }
            usleep(5_000)  // the keyboard drops packets sent back to back
        }
        return true
    }

    private func startAnimation(_ effect: Effect) {
        animationLock.lock()
        animationCancelled = false
        animationLock.unlock()
        let thread = Thread { [weak self] in
            var failures = 0
            while let self {
                self.animationLock.lock()
                let cancelled = self.animationCancelled
                self.animationLock.unlock()
                if cancelled { break }
                let ok = self.usb.sync { Self.write(Razer.frame(effect.next())) }
                if ok {
                    if failures > 0 { DispatchQueue.main.async { self.connected = true } }
                    failures = 0
                } else {
                    // Unplugged: keep the animation selected and retry every second.
                    failures += 1
                    if failures == 1 { DispatchQueue.main.async { self.connected = false } }
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
        thread.qualityOfService = .userInitiated
        thread.name = "Ornata animation"
        animation = thread
        thread.start()
    }
}
