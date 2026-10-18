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

    func packets(for keyboard: Keyboard) -> [[UInt8]] {
        switch self {
        case .animation: return []
        case .solid(let c): return Razer.solid(c)
        case .gradient(let a, let b): return Razer.gradient(a, b, for: keyboard)
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
    /// Which keyboard is plugged in and whether the app can drive it.
    @Published private(set) var detection: Detection
    /// False when the last command didn't reach the keyboard.
    @Published private(set) var reachable = true
    @Published var brightness: Double {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness") }
    }
    /// Drive keyboards that are on the list but haven't been tested on real hardware yet.
    @Published var allowUntested: Bool {
        didSet {
            UserDefaults.standard.set(allowUntested, forKey: "allowUntested")
            checkConnection()
        }
    }
    /// Speed of the current animation (or the wave), 1 = normal. Each effect keeps its own.
    @Published private(set) var speed = 1.0
    /// Set while the keyboard test runs: it drives this keyboard even if it's untested,
    /// and nothing it shows is saved.
    @Published private(set) var testing: Keyboard?

    static let speedRange = 0.25...4.0

    private let usb = DispatchQueue(label: "lumikey.usb")
    private var animation: Thread?
    private var animationCancelled = false
    private var animationSpeed = 1.0
    /// The keyboard the USB queue and animation thread write to. Guarded by `animationLock`.
    private var target: Keyboard?
    private let animationLock = NSLock()
    private var speeds = UserDefaults.standard.dictionary(forKey: "speeds") as? [String: Double] ?? [:]

    init() {
        brightness = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 100
        allowUntested = UserDefaults.standard.bool(forKey: "allowUntested")
        detection = .detect(allowUntested: UserDefaults.standard.bool(forKey: "allowUntested"))
        setTarget(detection.keyboard)
        if let data = UserDefaults.standard.data(forKey: "mode"),
           let saved = try? JSONDecoder().decode(Mode.self, from: data) {
            apply(saved)
        }
    }

    var keyboard: Keyboard? { testing ?? detection.keyboard }
    var connected: Bool { keyboard != nil && reachable }

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
        show(newMode)
    }

    /// Sends a mode to the keyboard without saving it.
    private func show(_ mode: Mode) {
        switch mode {
        case .animation(let id):
            if let info = Effects.info(id) { startAnimation(info.make()) }
        case .wave:
            send(Razer.wave(leftward: false, speed: speed))
        default:
            if let keyboard { send(mode.packets(for: keyboard)) }
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
        if case .animation = mode, testing == nil { mode = nil }
    }

    /// Looks for keyboards again; called every few seconds. Plugging a keyboard in puts the
    /// saved effect back on it.
    func checkConnection() {
        let found = Detection.detect(allowUntested: allowUntested)
        guard found != detection else { return }
        let previous = detection.keyboard
        detection = found
        guard testing == nil else { return }
        setTarget(found.keyboard)
        if let keyboard = found.keyboard, keyboard != previous {
            reachable = true
            // A running animation picks up the new keyboard by itself.
            if let mode, playingAnimation == nil { show(mode) }
        }
    }

    private func setTarget(_ keyboard: Keyboard?) {
        animationLock.lock()
        target = keyboard
        animationLock.unlock()
    }

    private var currentTarget: Keyboard? {
        animationLock.lock()
        defer { animationLock.unlock() }
        return target
    }

    // MARK: Keyboard test

    /// Takes over `keyboard` for the test: stops the current effect until `endTest`.
    func beginTest(_ keyboard: Keyboard) {
        testing = keyboard  // first, so stopping the animation doesn't forget it was playing
        stopAnimation()
        setTarget(keyboard)
    }

    /// Shows an effect during the test. Frames sized to the keyboard are sent as they are,
    /// so the test can light every single key.
    func testShow(_ effect: Effect) {
        stopAnimation()
        startAnimation(effect, speed: 1)
    }

    func testSend(_ packets: [[UInt8]]) {
        stopAnimation()
        send(packets)
    }

    /// Asks the keyboard for its firmware version; nil if it doesn't answer.
    func firmware(completion: @escaping (String?) -> Void) {
        let keyboard = currentTarget
        usb.async {
            let version = keyboard?.firmware()
            DispatchQueue.main.async { completion(version) }
        }
    }

    /// Hands the keyboard back and puts the saved effect and brightness back on it.
    func endTest() {
        guard testing != nil else { return }
        stopAnimation()
        testing = nil
        setTarget(detection.keyboard)
        send(Razer.brightness(brightness))
        if let mode { show(mode) }
    }

    // MARK: USB

    private func send(_ packets: [[UInt8]]) {
        let keyboard = currentTarget
        usb.async { [weak self] in
            let ok = keyboard.map { Self.write(packets, to: $0) } ?? false
            DispatchQueue.main.async { self?.reachable = ok }
        }
    }

    /// Blocking; call off the main thread.
    private static func write(_ packets: [[UInt8]], to keyboard: Keyboard) -> Bool {
        for p in packets {
            let result = p.withUnsafeBufferPointer { razer_send(keyboard.productID, keyboard.interface, $0.baseAddress) }
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

    private func startAnimation(_ effect: Effect, speed: Double? = nil) {
        animationLock.lock()
        animationCancelled = false
        animationSpeed = speed ?? self.speed
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
                let keyboard = self.target
                self.animationLock.unlock()
                if cancelled { break }
                progress += speed
                while progress >= 1 {
                    current = upcoming
                    upcoming = effect.next()
                    progress -= 1
                }
                let frame = Self.blend(current, upcoming, progress)
                let ok = keyboard.map { k in self.usb.sync { Self.write(Razer.frame(frame, for: k), to: k) } } ?? false
                if ok {
                    if failures > 0 { DispatchQueue.main.async { self.reachable = true } }
                    failures = 0
                } else {
                    // Unplugged: keep the animation selected and retry every second.
                    failures += 1
                    if failures == 1 { DispatchQueue.main.async { self.reachable = false } }
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
        thread.qualityOfService = .userInitiated
        thread.name = "Lumikey animation"
        animation = thread
        thread.start()
    }
}
