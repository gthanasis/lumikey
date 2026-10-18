import AppKit

/// Renders the animations onto a drawing of a full-size keyboard, for the README video.
/// Each key takes its colour from the grid cell under its centre, which is close to how
/// Razer lays out the Ornata V2's 6 × 22 grid.
enum Demo {
    static let width = 1280, height = 720
    static let fps = 28
    static let secondsPerEffect = 3.2
    static let fadeFrames = 10

    static let reel = ["rainbow", "fire", "rain", "ripple", "aurora", "snake", "plasma", "tetris", "fireworks", "pong", "ocean", "heartbeat"]

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let perEffect = Int(secondsPerEffect * Double(fps))
        let effects = reel.compactMap(Effects.info)
        var number = 0
        for (index, info) in effects.enumerated() {
            let effect = info.make()
            let following = index + 1 < effects.count ? effects[index + 1] : nil
            let nextEffect = following?.make()
            for f in 0..<perEffect {
                var grid = effect.next()
                var caption = (info.name, 1.0)
                // Cross-fade into the next effect over the last few frames.
                let fadeStart = perEffect - fadeFrames
                if let nextEffect, let following, f >= fadeStart {
                    let t = Double(f - fadeStart + 1) / Double(fadeFrames + 1)
                    grid = blend(grid, nextEffect.next(), t)
                    caption = t < 0.5 ? (info.name, 1 - t * 2) : (following.name, t * 2 - 1)
                }
                let image = draw(grid, caption: caption.0, captionAlpha: caption.1)
                number += 1
                write(image, to: folder.appendingPathComponent(String(format: "frame_%05d.png", number)))
            }
        }
    }

    private static func blend(_ a: Grid, _ b: Grid, _ t: Double) -> Grid {
        zip(a, b).map { ra, rb in
            zip(ra, rb).map { x, y in
                RGB(Double(x.r) + (Double(y.r) - Double(x.r)) * t,
                    Double(x.g) + (Double(y.g) - Double(x.g)) * t,
                    Double(x.b) + (Double(y.b) - Double(x.b)) * t)
            }
        }
    }

    private static func write(_ image: NSBitmapImageRep, to url: URL) {
        try? image.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: Layout

    /// A key in keyboard units (1 = one ordinary key), measured from the top left.
    struct Key { let label: String; let x, y, w, h: Double; let row: Int }

    /// US full-size layout: main block, navigation cluster, numpad.
    static let keys: [Key] = {
        var keys: [Key] = []
        /// Negative widths are gaps.
        func row(_ r: Int, _ y: Double, _ items: [(String, Double)]) {
            var x = 0.0
            for (label, w) in items {
                if w > 0 { keys.append(Key(label: label, x: x, y: y, w: w, h: 1, row: r)) }
                x += abs(w)
            }
        }
        let gap = ("", -0.25)
        // Row 0: function keys
        row(0, 0, [("esc", 1), ("", -1), ("F1", 1), ("F2", 1), ("F3", 1), ("F4", 1), ("", -0.5),
                   ("F5", 1), ("F6", 1), ("F7", 1), ("F8", 1), ("", -0.5), ("F9", 1), ("F10", 1), ("F11", 1), ("F12", 1),
                   gap, ("prt", 1), ("scr", 1), ("pause", 1)])
        let y1 = 1.4
        row(1, y1, [("`", 1), ("1", 1), ("2", 1), ("3", 1), ("4", 1), ("5", 1), ("6", 1), ("7", 1), ("8", 1), ("9", 1),
                    ("0", 1), ("-", 1), ("=", 1), ("delete", 2), gap, ("ins", 1), ("home", 1), ("pg up", 1), gap,
                    ("num", 1), ("/", 1), ("*", 1), ("−", 1)])
        row(2, y1 + 1, [("tab", 1.5), ("Q", 1), ("W", 1), ("E", 1), ("R", 1), ("T", 1), ("Y", 1), ("U", 1), ("I", 1), ("O", 1),
                        ("P", 1), ("[", 1), ("]", 1), ("\\", 1.5), gap, ("del", 1), ("end", 1), ("pg dn", 1), gap,
                        ("7", 1), ("8", 1), ("9", 1)])
        row(3, y1 + 2, [("caps", 1.75), ("A", 1), ("S", 1), ("D", 1), ("F", 1), ("G", 1), ("H", 1), ("J", 1), ("K", 1), ("L", 1),
                        (";", 1), ("'", 1), ("return", 2.25), gap, ("", -3), gap, ("4", 1), ("5", 1), ("6", 1)])
        row(4, y1 + 3, [("shift", 2.25), ("Z", 1), ("X", 1), ("C", 1), ("V", 1), ("B", 1), ("N", 1), ("M", 1), (",", 1), (".", 1),
                        ("/", 1), ("shift", 2.75), gap, ("", -1), ("↑", 1), ("", -1), gap, ("1", 1), ("2", 1), ("3", 1)])
        row(5, y1 + 4, [("ctrl", 1.25), ("⌘", 1.25), ("alt", 1.25), ("", 6.25), ("alt", 1.25), ("fn", 1.25), ("menu", 1.25),
                        ("ctrl", 1.25), gap, ("←", 1), ("↓", 1), ("→", 1), gap, ("0", 2), (".", 1)])
        // Tall numpad keys.
        keys.append(Key(label: "+", x: 21.5, y: y1 + 1, w: 1, h: 2, row: 2))
        keys.append(Key(label: "enter", x: 21.5, y: y1 + 3, w: 1, h: 2, row: 4))
        return keys
    }()

    static let layoutWidth = 22.5, layoutHeight = 6.4

    // MARK: Drawing

    static func draw(_ grid: Grid, caption: String, captionAlpha: Double) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Top-left origin, like the layout.
        let cg = context.cgContext
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.current = flipped

        let W = CGFloat(width), H = CGFloat(height)
        NSGradient(starting: NSColor(white: 0.09, alpha: 1), ending: NSColor(white: 0.03, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

        let unit: CGFloat = 50
        let boardW = CGFloat(layoutWidth) * unit, boardH = CGFloat(layoutHeight) * unit
        let origin = CGPoint(x: (W - boardW) / 2, y: 200)

        // Case.
        let caseRect = NSRect(x: origin.x - 22, y: origin.y - 22, width: boardW + 44, height: boardH + 44)
        NSColor(white: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: caseRect, xRadius: 18, yRadius: 18).fill()
        NSColor(white: 0.2, alpha: 1).setStroke()
        let edge = NSBezierPath(roundedRect: caseRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        edge.lineWidth = 1
        edge.stroke()

        let rows = grid.count, cols = grid.first?.count ?? 0
        func colour(for key: Key) -> RGB {
            let c = min(cols - 1, max(0, Int((key.x + key.w / 2) / layoutWidth * Double(cols))))
            return grid[min(rows - 1, key.row)][c]
        }
        func rect(_ key: Key) -> NSRect {
            NSRect(x: origin.x + CGFloat(key.x) * unit, y: origin.y + CGFloat(key.y) * unit,
                   width: CGFloat(key.w) * unit, height: CGFloat(key.h) * unit).insetBy(dx: 3, dy: 3)
        }

        // Light under the keys first, so it glows around every cap.
        for key in keys {
            let c = colour(for: key)
            let level = Double(max(c.r, c.g, c.b)) / 255
            guard level > 0.02 else { continue }
            let light = c.nsColor
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = light.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 16
            shadow.shadowOffset = .zero
            shadow.set()
            light.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: rect(key).insetBy(dx: -1, dy: -1), xRadius: 6, yRadius: 6).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Caps with see-through legends.
        for key in keys {
            let c = colour(for: key)
            let r = rect(key).insetBy(dx: 2.5, dy: 2.5)
            NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.1, alpha: 1))!
                .draw(in: NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5), angle: 90)
            guard !key.label.isEmpty else { continue }
            let level = Double(max(c.r, c.g, c.b)) / 255
            let legend = level > 0.02
                ? c.nsColor.blended(withFraction: 0.35, of: .white)!
                : NSColor(white: 0.32, alpha: 1)
            let size: CGFloat = key.label.count > 2 ? 11 : 15
            let text = NSAttributedString(string: key.label, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium),
                .foregroundColor: legend,
            ])
            let t = text.size()
            text.draw(at: NSPoint(x: r.minX + (key.label.count > 2 ? 7 : (r.width - t.width) / 2), y: r.minY + 6))
        }

        // Title and caption.
        let title = NSMutableAttributedString(string: "Lumi", attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white,
        ])
        title.append(NSAttributedString(string: "key", attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.27, green: 0.84, blue: 0.17, alpha: 1),
        ]))
        title.draw(at: NSPoint(x: origin.x - 22, y: origin.y - 98))
        let sub = NSAttributedString(string: "Per-key lighting for Razer keyboards on macOS", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular), .foregroundColor: NSColor(white: 0.6, alpha: 1),
        ])
        sub.draw(at: NSPoint(x: origin.x - 20, y: origin.y - 58))

        let cap = NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(captionAlpha),
        ])
        cap.draw(at: NSPoint(x: (W - cap.size().width) / 2, y: origin.y + boardH + 52))

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
