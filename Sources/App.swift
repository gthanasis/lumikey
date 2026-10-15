import SwiftUI

@main
struct OrnataLightsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(lights: delegate.lights, onOpenWindow: delegate.showWindow)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let lights = Lights()
    private var window: NSWindow?
    private var connectionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--snapshot <file.png>`: render the window to an image and quit (no screen
        // recording permission needed). Used to check the layout when building.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let view = self.window?.contentView, let layer = view.layer {
                let scale = self.window?.backingScaleFactor ?? 2
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
            let w = NSWindow(contentViewController: NSHostingController(rootView: ControlPanel(lights: lights)))
            w.title = "Ornata Lights"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
