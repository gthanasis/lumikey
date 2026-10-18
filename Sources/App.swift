import SwiftUI

enum Project {
    static let repo = URL(string: "https://github.com/gthanasis/lumikey")!
}

@main
struct LumikeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(lights: delegate.lights, onOpenWindow: delegate.showWindow, onTest: delegate.showTest)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    lazy var lights = Lights()
    private var window: NSWindow?
    private var testWindow: NSWindow?
    private var connectionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--snapshot <file.png>`: render the window to an image and quit (no screen
        // recording permission needed). Used to check the layout when building.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
            return
        }
        // `--snapshot-test <file.png>`: the same for the keyboard test window.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-test"), i + 1 < CommandLine.arguments.count {
            showTest()
            snapshot(testWindow, to: CommandLine.arguments[i + 1])
            return
        }
        // `--probe`: list the Razer devices, ask the keyboard for its firmware, and quit.
        if CommandLine.arguments.contains("--probe") {
            probe()
            NSApp.terminate(nil)
            return
        }
        // `--render-demo <folder>`: draw the animations on a picture of the keyboard, one PNG
        // per frame, and quit. scripts/make-demo.sh turns them into the README video.
        if let i = CommandLine.arguments.firstIndex(of: "--render-demo"), i + 1 < CommandLine.arguments.count {
            Demo.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            NSApp.terminate(nil)
            return
        }
        // First launch: show the window, so it's obvious the app started even if the
        // menu bar icon is hidden (notch, or too many menu bar items).
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showWindow()
        }
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.lights.checkConnection()
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) brings up the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        lights.stopAnimation()
    }

    private func snapshot(to path: String) {
        showWindow()
        snapshot(window, to: path)
    }

    private func snapshot(_ window: NSWindow?, to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let view = window?.contentView, let layer = view.layer {
                let scale = window?.backingScaleFactor ?? 2
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                                           pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
                ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
                // Layers render bottom-up; flip so the PNG reads top-down.
                ctx.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
                ctx.scaleBy(x: scale, y: -scale)
                layer.render(in: ctx)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ControlPanel(lights: lights, onTest: showTest)))
            w.title = "Lumikey"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate {
    private func probe() {
        let devices = RazerDevice.connected()
        if devices.isEmpty { print("No Razer devices connected.") }
        for device in devices {
            guard let k = device.keyboard else {
                print("\(device.usbID)  \(device.name): not supported")
                continue
            }
            let answer = k.firmware().map { "answered, firmware \($0)" } ?? "no answer (quit Lumikey first if it's playing an animation)"
            print("\(k.usbID)  \(k.name): \(k.verified ? "supported" : "untested"), interface \(k.interface), \(k.rows)x\(k.cols), \(answer)")
        }
    }

    func showTest() {
        if testWindow == nil {
            let view = KeyboardTestView(lights: lights) { [weak self] in self?.testWindow?.close() }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Test Keyboard"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            testWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        testWindow?.makeKeyAndOrderFront(nil)
    }

    /// Closing the test (at any step) gives the keyboard back.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === testWindow else { return }
        lights.endTest()
        testWindow = nil
    }
}
