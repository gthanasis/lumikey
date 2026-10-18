import AppKit
import SwiftUI

/// Walks someone through checking that their keyboard works with the app, one effect at a
/// time, then turns their answers into a report they can send.
struct KeyboardTestView: View {
    @ObservedObject var lights: Lights
    var onClose: () -> Void

    @State private var devices: [RazerDevice] = []
    @State private var keyboard: Keyboard?
    /// nil before the first step; `steps.count` once every question is answered.
    @State private var stepIndex: Int?
    @State private var firmware: String?
    @State private var answered: Bool?
    @State private var answers: [String: Answer] = [:]
    @State private var typed = ""
    @State private var copied = false

    enum Answer: String { case yes = "Yes", partly = "Partly", no = "No" }

    struct Step {
        let id: String
        let title: String
        let detail: String
        let question: String
        let show: (Lights, Keyboard) -> Void
    }

    private var steps: [Step] {
        var steps: [Step] = [
            Step(id: "white", title: "All keys white",
                 detail: "Every key should now be lit white at full brightness.",
                 question: "Is every key lit white?") { lights, _ in
                lights.testSend(Razer.brightness(100) + Razer.solid(RGB(r: 255, g: 255, b: 255)))
            },
        ]
        if keyboard?.hasPerKeyLighting ?? true {
            steps += [
                Step(id: "rows", title: "Rows",
                     detail: "One row of keys at a time lights up, from the top row down, then it starts again.",
                     question: "Did every row light up, one at a time?") { lights, k in
                    lights.testShow(Sweep(keyboard: k, vertical: true))
                },
                Step(id: "columns", title: "Columns",
                     detail: "A line sweeps from the left edge of the keyboard to the right edge.",
                     question: "Did the line cross the whole keyboard without skipping any keys?") { lights, k in
                    lights.testShow(Sweep(keyboard: k, vertical: false))
                },
            ]
        }
        steps += [
            Step(id: "animation", title: "Animation",
                 detail: "This is Rainbow, one of the app's animations.",
                 question: "Do you see a moving rainbow?") { lights, _ in
                lights.testShow(Rainbow())
            },
            Step(id: "wave", title: "Wave",
                 detail: "This one is built into the keyboard: the app only switches it on.",
                 question: "Is a wave of colour moving across the keys?") { lights, _ in
                lights.testSend(Razer.wave(leftward: false))
            },
            Step(id: "typing", title: "Typing",
                 detail: "Type a few letters in the box. Each key should light up green and fade.",
                 question: "Did the keys light up as you pressed them?") { lights, _ in
                lights.testSend(Razer.reactive(RGB(r: 68, g: 214, b: 44), speed: 2))
            },
            Step(id: "brightness", title: "Brightness",
                 detail: "The keys go back to white, at a quarter of full brightness.",
                 question: "Is the keyboard clearly dimmer than in the first step?") { lights, _ in
                lights.testSend(Razer.solid(RGB(r: 255, g: 255, b: 255)) + Razer.brightness(25))
            },
        ]
        return steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Test your keyboard").font(.title3.weight(.semibold))
            content
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: start)
    }

    @ViewBuilder private var content: some View {
        if devices.isEmpty {
            Text("No Razer keyboard is plugged in. Connect it with a USB cable (not wireless) and try again.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Look again", action: start)
                Spacer()
                Button("Close", action: onClose)
            }
        } else if keyboard == nil {
            unsupported
        } else if let i = stepIndex, i < steps.count {
            step(steps[i], number: i + 1)
        } else if stepIndex == nil {
            intro
        } else {
            results
        }
    }

    // MARK: Screens

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            deviceSummary
            Text("The test shows \(steps.count) things on the keyboard and asks whether each one looks right. It takes about a minute. Your own effect comes back afterwards.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button("Start") { go(to: 0) }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var deviceSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let keyboard {
                Text(keyboard.name).font(.headline)
                Text("\(keyboard.usbID) · \(keyboard.rows) × \(keyboard.cols) lights · \(keyboard.verified ? "tested" : "not tested yet")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch answered {
            case .some(true):
                Label("It answered (firmware \(firmware ?? "unknown"))", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .some(false):
                Label("It didn't answer. The lights may still work, so carry on.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            case .none:
                Label("Asking the keyboard…", systemImage: "ellipsis.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ step: Step, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(number) of \(steps.count): \(step.title)").font(.headline)
            Text(step.detail).fixedSize(horizontal: false, vertical: true)
            if step.id == "typing" {
                TextField("Type here", text: $typed).textFieldStyle(.roundedBorder)
            }
            Text(step.question).font(.callout.weight(.semibold))
            HStack {
                Button("Back") { go(to: number - 2) }.disabled(number == 1)
                Spacer()
                ForEach([Answer.no, .partly, .yes], id: \.self) { answer in
                    Button(answer.rawValue) {
                        answers[step.id] = answer
                        go(to: number)
                    }
                    .keyboardShortcut(answer == .yes ? .defaultAction : nil)
                }
            }
        }
    }

    private var results: some View {
        let failed = steps.filter { answers[$0.id] != .yes }
        return VStack(alignment: .leading, spacing: 12) {
            if failed.isEmpty {
                Label("Everything worked.", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                Text("Please send the report so the next version can list this keyboard as working.")
            } else {
                Label("\(failed.count) of \(steps.count) didn't look right.", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text("Please send the report anyway: it shows what to fix. Mention which keys were wrong if you can.")
            }
            reportBox
            HStack {
                Button(copied ? "Copied" : "Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                Button("Open a GitHub issue") { NSWorkspace.shared.open(issueURL) }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var unsupported: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("None of these are supported yet:")
            ForEach(devices, id: \.productID) { device in
                Text("• \(device.name) (\(device.usbID))")
            }
            Text("If one of them is a keyboard, send a report and support may come in a later version.")
                .fixedSize(horizontal: false, vertical: true)
            reportBox
            HStack {
                Button("Open a GitHub issue") { NSWorkspace.shared.open(issueURL) }
                Spacer()
                Button("Close", action: onClose)
            }
        }
    }

    private var reportBox: some View {
        ScrollView {
            Text(report).font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .frame(height: 130)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }

    // MARK: Running the test

    private func start() {
        devices = RazerDevice.connected()
        keyboard = devices.lazy.compactMap(\.keyboard).first
        stepIndex = nil
        answers = [:]
        guard let keyboard else { return }
        lights.beginTest(keyboard)
        answered = nil
        lights.firmware { version in
            firmware = version
            answered = version != nil
        }
    }

    private func go(to index: Int) {
        stepIndex = index
        copied = false
        if index < steps.count, let keyboard { steps[index].show(lights, keyboard) }
        if index == steps.count { lights.endTest() }
    }

    // MARK: Report

    private var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        var lines = [
            "App: Lumikey \(version)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)",
            "Razer devices: " + devices.map { "\($0.name) (\($0.usbID))" }.joined(separator: ", "),
        ]
        if let keyboard {
            lines.append("Tested: \(keyboard.name) (\(keyboard.usbID)), \(keyboard.rows)x\(keyboard.cols), interface \(keyboard.interface)")
            lines.append("Answered: \(answered == true ? "yes, firmware \(firmware ?? "?")" : "no")")
            for step in steps {
                lines.append("\(step.title): \(answers[step.id]?.rawValue ?? "not answered")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var issueURL: URL {
        let name = keyboard?.name ?? devices.first?.name ?? "Razer keyboard"
        let outcome = keyboard == nil ? "support request" : (steps.allSatisfy { answers[$0.id] == .yes } ? "works" : "problems")
        var url = URLComponents(url: Project.repo.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "title", value: "\(name): \(outcome)"),
            URLQueryItem(name: "body", value: "```\n\(report)\n```\n\nAnything else (which keys were wrong, etc.):\n"),
        ]
        return url.url!
    }
}

/// Lights one row (or column) at a time across the keyboard's real grid, so every LED is checked.
final class Sweep: Effect {
    let keyboard: Keyboard, vertical: Bool
    var t = 0

    init(keyboard: Keyboard, vertical: Bool) {
        self.keyboard = keyboard
        self.vertical = vertical
    }

    func next() -> Grid {
        defer { t += 1 }
        let lines = vertical ? keyboard.rows : keyboard.cols
        let framesPerLine = vertical ? 14 : 5  // half a second per row, a fifth per column
        let lit = (t / framesPerLine) % lines
        let colour = RGB(r: 68, g: 214, b: 44)
        return (0..<keyboard.rows).map { r in
            (0..<keyboard.cols).map { c in (vertical ? r : c) == lit ? colour : .black }
        }
    }
}
