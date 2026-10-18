import ServiceManagement
import SwiftUI

private let razerGreen = Color(red: 0.27, green: 0.84, blue: 0.17)

private let presets: [String] = ["ff0000", "ff7a00", "ffe600", "44d62c", "00c8ff", "3d5cff", "b44dff", "ff3fa4", "ffffff"]

struct ControlPanel: View {
    @ObservedObject var lights: Lights
    var onOpenWindow: (() -> Void)?
    var onTest: () -> Void

    @AppStorage("solid") private var solid = "44d62c"
    @AppStorage("gradientA") private var gradientA = "ff0080"
    @AppStorage("gradientB") private var gradientB = "00c8ff"
    @AppStorage("breathA") private var breathA = "7b5cff"
    @AppStorage("breathB") private var breathB = "ff3fa4"
    @AppStorage("typing") private var typing = "00c8ff"
    @AppStorage("typingSpeed") private var typingSpeed = 3
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            notice
            section("Animations") {
                animationGrid
                speedControl
            }
            section("Saved to keyboard") { savedEffects }
            section("Brightness") { brightness }
            footer
        }
        .padding(16)
        .frame(width: 400)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Lumi").font(.headline) + Text("key").font(.headline).foregroundColor(razerGreen)
            Spacer()
            if lights.testing != nil {
                Text("Testing keyboard…").font(.caption).foregroundStyle(.secondary)
            } else if !lights.connected {
                Label(lights.keyboard == nil ? "No keyboard found" : "Keyboard not responding",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(lights.mode.map { lights.playingAnimation != nil ? "Playing \($0.label.lowercased())" : $0.label } ?? "Ready")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Explains a keyboard the app can't (or isn't sure it can) drive.
    @ViewBuilder private var notice: some View {
        switch lights.detection {
        case .untested(let keyboard):
            noticeBox {
                Text("Found a **\(keyboard.name)**. It should work, but nobody has tried it with this app yet.")
                HStack {
                    Button("Use it anyway") { lights.allowUntested = true }
                    Button("Test it…", action: onTest)
                }
            }
        case .unsupported(let devices):
            noticeBox {
                Text("This app doesn't support \(ListFormatter.localizedString(byJoining: devices.map(\.name))) yet.")
                Button("Send a report…", action: onTest)
            }
        case .ready(let keyboard) where !keyboard.verified && lights.testing == nil:
            noticeBox {
                Text("**\(keyboard.name)** support is experimental. If you run the test, the next version can mark it as working.")
                Button("Test it…", action: onTest)
            }
        default:
            EmptyView()
        }
    }

    private func noticeBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            content()
        }
    }

    // MARK: Animations

    private var animationGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Effects.all) { info in
                let active = lights.playingAnimation == info.id
                Button {
                    if active { lights.stopAnimation() } else { lights.apply(.animation(info.id)) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: info.symbol).font(.system(size: 17)).frame(height: 20)
                        Text(info.name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(active ? razerGreen.opacity(0.22) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? razerGreen : .clear, lineWidth: 1.5))
                    .foregroundStyle(active ? razerGreen : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(active ? "Click to stop" : info.subtitle.capitalized)
            }
        }
    }

    /// Logarithmic, so ½× and 2× sit the same distance either side of normal.
    private var speedControl: some View {
        HStack {
            Image(systemName: "tortoise").foregroundStyle(.secondary).help("Slower")
            Slider(
                value: Binding(get: { log2(lights.speed) }, set: { lights.setSpeed(pow(2, $0)) }),
                in: log2(Lights.speedRange.lowerBound)...log2(Lights.speedRange.upperBound)
            ) {
                EmptyView()
            } onEditingChanged: { editing in
                // Snap back to exactly 1× when released close to it.
                if !editing, abs(log2(lights.speed)) < 0.12 { lights.setSpeed(1) }
            }
            .tint(razerGreen)
            Image(systemName: "hare").foregroundStyle(.secondary).help("Faster")
            Text(speedLabel).font(.callout.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
        .disabled(!lights.canChangeSpeed)
        .opacity(lights.canChangeSpeed ? 1 : 0.45)
        .help(lights.canChangeSpeed ? "Speed of the current effect" : "Pick an animation (or Wave) to change its speed")
    }

    private var speedLabel: String {
        String(format: "%.2g×", lights.speed)  // 0.25×, 0.5×, 1×, 1.5×, 4×
    }

    // MARK: Saved effects

    private var savedEffects: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Solid") {
                ColorPicker("", selection: color($solid), supportsOpacity: false).labelsHidden()
                HStack(spacing: 4) {
                    ForEach(presets, id: \.self) { hex in
                        Button { solid = hex; lights.apply(.solid(RGB(hex: hex))) } label: {
                            Circle().fill(Color(nsColor: RGB(hex: hex).nsColor)).frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Button("Set") { lights.apply(.solid(RGB(hex: solid))) }
            }
            row("Gradient") {
                ColorPicker("", selection: color($gradientA), supportsOpacity: false).labelsHidden()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                ColorPicker("", selection: color($gradientB), supportsOpacity: false).labelsHidden()
                Spacer()
                Button("Set") { lights.apply(.gradient(RGB(hex: gradientA), RGB(hex: gradientB))) }
            }
            row("Breathing") {
                ColorPicker("", selection: color($breathA), supportsOpacity: false).labelsHidden()
                ColorPicker("", selection: color($breathB), supportsOpacity: false).labelsHidden()
                Spacer()
                Menu("Set") {
                    Button("First colour") { lights.apply(.breathing([RGB(hex: breathA)])) }
                    Button("Both colours") { lights.apply(.breathing([RGB(hex: breathA), RGB(hex: breathB)])) }
                    Button("Random colours") { lights.apply(.breathing([])) }
                }
                .fixedSize()
            }
            row("Typing") {
                ColorPicker("", selection: color($typing), supportsOpacity: false).labelsHidden()
                Picker("", selection: $typingSpeed) {
                    Text("Quick fade").tag(1)
                    Text("Medium fade").tag(2)
                    Text("Slow fade").tag(3)
                    Text("Slowest fade").tag(4)
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Set") { lights.apply(.typing(RGB(hex: typing), speed: UInt8(typingSpeed))) }
            }
            HStack {
                Button("Spectrum cycle") { lights.apply(.spectrum) }
                Button("Wave") { lights.apply(.wave) }
                Spacer()
                Button("Lights off") { lights.apply(.off) }
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
            content()
        }
    }

    /// Bridges a stored hex string to a SwiftUI colour picker.
    private func color(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: RGB(hex: hex.wrappedValue).nsColor) },
            set: { new in
                let c = RGB(NSColor(new))
                hex.wrappedValue = String(format: "%02x%02x%02x", c.r, c.g, c.b)
            }
        )
    }

    // MARK: Brightness

    private var brightness: some View {
        HStack {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: Binding(get: { lights.brightness }, set: { lights.setBrightness($0.rounded()) }), in: 0...100)
                .tint(razerGreen)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Text("\(Int(lights.brightness))%").font(.callout.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Toggle("Start at login", isOn: Binding(get: { startAtLogin }, set: setStartAtLogin))
                    .toggleStyle(.checkbox)
                Spacer()
                if let onOpenWindow {
                    Button("Open window", action: onOpenWindow)
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Test keyboard…", action: onTest).buttonStyle(.link)
                Spacer()
                Link("About", destination: Project.repo)
            }
            .font(.caption)
        }
    }

    private func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
        if on && SMAppService.mainApp.status == .requiresApproval {
            loginError = "Approve it in System Settings › General › Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
