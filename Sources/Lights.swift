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
    /// Speed of the current animation (or the wave), 1 = normal. Each effect keeps its own.
    @Published private(set) var speed = 1.0

    static let speedRange = 0.25...4.0

    private let usb = DispatchQueue(label: "ornata.usb")
    private var animation: Thread?
    private var animationCancelled = false
    private var animationSpeed = 1.0
    private let animationLock = NSLock()
    private var speeds = UserDefaults.standard.dictionary(forKey: "speeds") as? [String: Double] ?? [:]

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

    /// What the speed control applies to right now, if anything.
    private var speedKey: String? {
        switch mode {
        case .animation(let id): return id
        case .wave: return "wave"
        default: return nil
        }
    }

    var canChangeSpeed: Bool { speedKey != nil }

    func setSpeed(_ value: Double) {
        guard let key = speedKey else { return }
        let value = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, value))
        speed = value
        speeds[key] = value
        UserDefaults.standard.set(speeds, forKey: "speeds")
        if case .wave = mode {
            send(Razer.wave(leftward: false, speed: value))
        } else {
            animationLock.lock()
            animationSpeed = value
            animationLock.unlock()
        }
    }

    func apply(_ newMode: Mode) {
        stopAnimation()
        mode = newMode
        if let data = try? JSONEncoder().encode(newMode) { UserDefaults.standard.set(data, forKey: "mode") }
        speed = speedKey.flatMap { speeds[$0] } ?? 1
        switch newMode {
        case .animation(let id):
            if let info = Effects.info(id) { startAnimation(info.make()) }
        case .wave:
            send(Razer.wave(leftward: false, speed: speed))
        default:
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

    /// Mixes two frames; t = 0 gives `a`, t = 1 gives `b`.
    private static func blend(_ a: Grid, _ b: Grid, _ t: Double) -> Grid {
        if t <= 0 { return a }
        return zip(a, b).map { rowA, rowB in
            zip(rowA, rowB).map { x, y in
                RGB(Double(x.r) + (Double(y.r) - Double(x.r)) * t,
                    Double(x.g) + (Double(y.g) - Double(x.g)) * t,
                    Double(x.b) + (Double(y.b) - Double(x.b)) * t)
            }
        }
    }

    private func startAnimation(_ effect: Effect) {
        animationLock.lock()
        animationCancelled = false
        animationSpeed = speed
        animationLock.unlock()
        let thread = Thread { [weak self] in
            var failures = 0
            // Speed works on any effect without changing it: each sent frame moves the effect
            // forward by `speed` steps. Faster runs several steps per frame; slower shows
            // blends between two steps, so slow motion stays smooth.
            var current = effect.next()
            var upcoming = effect.next()
            var progress = 0.0
            while let self {
                self.animationLock.lock()
                let cancelled = self.animationCancelled
                let speed = self.animationSpeed
                self.animationLock.unlock()
                if cancelled { break }
                progress += speed
                while progress >= 1 {
                    current = upcoming
                    upcoming = effect.next()
                    progress -= 1
                }
                let frame = Self.blend(current, upcoming, progress)
                let ok = self.usb.sync { Self.write(Razer.frame(frame)) }
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
