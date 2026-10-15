import Foundation

/// An animation produces one frame per call, about 28 frames a second.
protocol Effect: AnyObject {
    func next() -> Grid
}

struct EffectInfo: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let make: () -> Effect
}

enum Effects {
    static let all: [EffectInfo] = [
        .init(id: "rainbow", name: "Rainbow", subtitle: "diagonal", symbol: "rainbow", make: Rainbow.init),
        .init(id: "rain", name: "Rain", subtitle: "matrix", symbol: "cloud.rain", make: Rain.init),
        .init(id: "fire", name: "Fire", subtitle: "flicker", symbol: "flame", make: Fire.init),
        .init(id: "scanner", name: "Scanner", subtitle: "KITT", symbol: "car.side", make: Scanner.init),
        .init(id: "ripple", name: "Ripple", subtitle: "rings", symbol: "circle.circle", make: Ripple.init),
        .init(id: "stars", name: "Stars", subtitle: "twinkle", symbol: "sparkles", make: Stars.init),
        .init(id: "aurora", name: "Aurora", subtitle: "northern lights", symbol: "wind", make: Aurora.init),
        .init(id: "plasma", name: "Plasma", subtitle: "demoscene", symbol: "drop.halffull", make: Plasma.init),
        .init(id: "snake", name: "Snake", subtitle: "hungry", symbol: "point.topleft.down.to.point.bottomright.curvepath", make: Snake.init),
        .init(id: "heartbeat", name: "Heartbeat", subtitle: "lub-dub", symbol: "heart", make: Heartbeat.init),
        .init(id: "police", name: "Police", subtitle: "red & blue", symbol: "light.beacon.max", make: Police.init),
        .init(id: "ocean", name: "Ocean", subtitle: "waves", symbol: "water.waves", make: Ocean.init),
        .init(id: "confetti", name: "Confetti", subtitle: "party", symbol: "party.popper", make: Confetti.init),
        .init(id: "equalizer", name: "Equalizer", subtitle: "bars", symbol: "chart.bar", make: Equalizer.init),
        .init(id: "life", name: "Life", subtitle: "Conway", symbol: "square.grid.3x3.middle.filled", make: Life.init),
        .init(id: "lava", name: "Lava lamp", subtitle: "blobs", symbol: "lamp.table", make: Lava.init),
        .init(id: "tetris", name: "Tetris", subtitle: "stacking", symbol: "square.stack.3d.down.right", make: Tetris.init),
        .init(id: "pong", name: "Pong", subtitle: "1972", symbol: "gamecontroller", make: Pong.init),
        .init(id: "fireworks", name: "Fireworks", subtitle: "boom", symbol: "fireworks", make: Fireworks.init),
        .init(id: "storm", name: "Storm", subtitle: "lightning", symbol: "cloud.bolt.rain", make: Storm.init),
        .init(id: "clock", name: "Clock", subtitle: "live time", symbol: "clock", make: Clock.init),
        .init(id: "cpu", name: "CPU", subtitle: "live load", symbol: "cpu", make: CPU.init),
        .init(id: "candle", name: "Candle", subtitle: "cosy", symbol: "flame.circle", make: Candle.init),
        .init(id: "dna", name: "DNA", subtitle: "helix", symbol: "allergens", make: DNA.init),
    ]

    static func info(_ id: String) -> EffectInfo? { all.first { $0.id == id } }
}

// MARK: - Helpers

private let R = Razer.rows, C = Razer.cols

private func blank(_ c: RGB = .black) -> Grid { Array(repeating: Array(repeating: c, count: C), count: R) }

private func hsv(_ h: Double, _ s: Double = 1, _ v: Double = 1) -> RGB {
    let h = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(h), f = h - Double(i)
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    let (r, g, b): (Double, Double, Double)
    switch i % 6 {
    case 0: (r, g, b) = (v, t, p)
    case 1: (r, g, b) = (q, v, p)
    case 2: (r, g, b) = (p, v, t)
    case 3: (r, g, b) = (p, q, v)
    case 4: (r, g, b) = (t, p, v)
    default: (r, g, b) = (v, p, q)
    }
    return RGB(r * 255, g * 255, b * 255)
}

private func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a..<b) }

// MARK: - Effects

final class Rainbow: Effect {
    var t = 0.0
    func next() -> Grid {
        defer { t += 0.02 }
        return (0..<R).map { r in (0..<C).map { c in hsv(Double(c) / Double(C) + Double(r) / 24 - t) } }
    }
}

/// Matrix-style: each column has a falling drop with a fading green trail.
final class Rain: Effect {
    var heads = (0..<C).map { _ in rnd(-6, 0) }
    var speeds = (0..<C).map { _ in rnd(0.15, 0.4) }
    func next() -> Grid {
        var g = blank()
        for c in 0..<C {
            for r in 0..<R {
                let d = heads[c] - Double(r)
                if d >= 0 && d < 4 {
                    let v = 1 - d / 4
                    g[r][c] = d < 1 ? RGB(r: 180, g: 255, b: 180) : RGB(0, 255 * v, 40 * v)
                }
            }
            heads[c] += speeds[c]
            if heads[c] - 4 > Double(R) {
                heads[c] = rnd(-4, 0)
                speeds[c] = rnd(0.15, 0.4)
            }
        }
        return g
    }
}

/// Heat rises from the space bar row and cools as it climbs.
final class Fire: Effect {
    var heat = Array(repeating: Array(repeating: 0.0, count: C), count: R)
    func next() -> Grid {
        heat[R - 1] = (0..<C).map { _ in rnd(0.6, 1) }
        for r in 0..<(R - 1) {
            let below = heat[r + 1]
            for c in 0..<C {
                let avg = (below[c] * 2 + below[max(c - 1, 0)] + below[min(c + 1, C - 1)]) / 4
                heat[r][c] = max(0, avg - rnd(0.05, 0.22))
            }
        }
        return heat.map { row in row.map { h in
            RGB(255 * min(1, h * 1.6), 255 * max(0, h - 0.45) * 1.4, 255 * max(0, h - 0.85) * 4)
        } }
    }
}

/// KITT from Knight Rider.
final class Scanner: Effect {
    var pos = 0.0, step = 0.5
    var trail = Array(repeating: 0.0, count: C)
    func next() -> Grid {
        trail = trail.map { $0 * 0.7 }
        trail[Int(pos)] = 1
        pos += step
        if pos <= 0 || pos >= Double(C - 1) {
            step = -step
            pos = max(0, min(Double(C - 1), pos))
        }
        let row = trail.map { RGB(255 * $0, 0, 0) }
        return Array(repeating: row, count: R)
    }
}

/// Coloured rings spreading out from random keys.
final class Ripple: Effect {
    struct Ring { var r: Double, c: Double, radius: Double, hue: Double }
    var rings: [Ring] = []
    var t = 0
    func next() -> Grid {
        if t % 18 == 0 {
            rings.append(Ring(r: Double(Int.random(in: 0..<R)), c: Double(Int.random(in: 0..<C)), radius: 0, hue: rnd(0, 1)))
        }
        t += 1
        var acc = Array(repeating: Array(repeating: (0.0, 0.0, 0.0), count: C), count: R)
        for i in rings.indices {
            let ring = rings[i]
            for r in 0..<R {
                for c in 0..<C {
                    let d = hypot((Double(r) - ring.r) * 1.8, Double(c) - ring.c)
                    let v = max(0, 1 - abs(d - ring.radius) / 1.5) * max(0, 1 - ring.radius / 22)
                    if v > 0 {
                        let col = hsv(ring.hue, 1, v)
                        acc[r][c].0 += Double(col.r); acc[r][c].1 += Double(col.g); acc[r][c].2 += Double(col.b)
                    }
                }
            }
            rings[i].radius += 0.5
        }
        rings.removeAll { $0.radius >= 22 }
        return acc.map { row in row.map { RGB($0.0, $0.1, $0.2) } }
    }
}

/// Deep blue night sky with keys twinkling white.
final class Stars: Effect {
    var level = Array(repeating: Array(repeating: 0.0, count: C), count: R)
    func next() -> Grid {
        for r in 0..<R {
            for c in 0..<C {
                level[r][c] *= 0.88
                if rnd(0, 1) < 0.015 { level[r][c] = 1 }
            }
        }
        return level.map { row in row.map { v in RGB(255 * v, 255 * v, 40 + 215 * v) } }
    }
}

/// Slow northern lights: green and violet curtains drifting sideways.
final class Aurora: Effect {
    var t = 0.0
    func next() -> Grid {
        defer { t += 0.04 }
        return (0..<R).map { r in (0..<C).map { c in
            let x = Double(c)
            let wave = sin(x * 0.35 + t) + sin(x * 0.17 - t * 0.7 + Double(r) * 0.5)
            let v = pow(max(0, wave / 2), 1.5)
            let hue = 0.38 + 0.4 * (0.5 + 0.5 * sin(x * 0.1 + t * 0.3))
            return hsv(hue, 0.9, 0.08 + 0.92 * v)
        } }
    }
}

/// Classic demoscene plasma: overlapping sine fields mapped to hue.
final class Plasma: Effect {
    var t = 0.0
    func next() -> Grid {
        defer { t += 0.08 }
        return (0..<R).map { r in (0..<C).map { c in
            let x = Double(c), y = Double(r)
            let v = sin(x * 0.4 + t) + sin(y * 0.6 - t * 1.3) + sin((x + y) * 0.3 + t * 0.7)
                + sin(hypot(x - 11, (y - 3) * 2) * 0.5 - t)
            return hsv(v / 8 + t * 0.05)
        } }
    }
}

/// A rainbow snake chasing a blinking white key, growing each time it eats it.
final class Snake: Effect {
    struct P: Equatable { var r: Int, c: Int }
    var body = [P(r: 3, c: 5), P(r: 3, c: 4), P(r: 3, c: 3)]
    var dir = P(r: 0, c: 1)
    var food = P(r: Int.random(in: 0..<R), c: Int.random(in: 0..<C))
    var tick = 0

    func wrap(_ p: P) -> P { P(r: (p.r + R) % R, c: (p.c + C) % C) }

    func next() -> Grid {
        if tick % 3 == 0 {
            let head = body[0]
            // Head towards the food, without reversing or biting itself.
            let options = [P(r: 0, c: 1), P(r: 0, c: -1), P(r: 1, c: 0), P(r: -1, c: 0)].sorted {
                let a = abs(head.r + $0.r - food.r) + abs(head.c + $0.c - food.c)
                let b = abs(head.r + $1.r - food.r) + abs(head.c + $1.c - food.c)
                return Double(a) + rnd(0, 1) < Double(b) + rnd(0, 1)
            }
            for d in options where d != P(r: -dir.r, c: -dir.c) && !body.contains(wrap(P(r: head.r + d.r, c: head.c + d.c))) {
                dir = d
                break
            }
            let nxt = wrap(P(r: head.r + dir.r, c: head.c + dir.c))
            if body.contains(nxt) { body = Array(body.prefix(3)) }
            body.insert(nxt, at: 0)
            if nxt == food {
                while body.contains(food) { food = P(r: Int.random(in: 0..<R), c: Int.random(in: 0..<C)) }
            } else {
                body.removeLast()
            }
            if body.count > 30 { body = Array(body.prefix(3)) }
        }
        var g = blank()
        g[food.r][food.c] = tick % 10 < 7 ? RGB(r: 255, g: 255, b: 255) : RGB(r: 60, g: 60, b: 60)
        for (i, p) in body.enumerated() {
            g[p.r][p.c] = hsv(Double(i) / 20 + Double(tick) / 200, 1, i == 0 ? 1 : 0.7)
        }
        tick += 1
        return g
    }
}

/// A red pulse beating out from the middle of the keyboard: lub-dub, pause.
final class Heartbeat: Effect {
    var t = 0
    func next() -> Grid {
        let phase = t % 40
        t += 1
        let radius = phase < 14 ? Double(phase) * 0.9 : phase < 26 ? Double(phase - 8) * 0.9 : -10
        return (0..<R).map { r in (0..<C).map { c in
            let d = hypot(Double(r - 3) * 2, Double(c - 11))
            let v = max(0, 1 - abs(d - radius) / 2.5) * max(0, 1 - radius / 14)
            return RGB(20 + 235 * v, 0, 30 * v)
        } }
    }
}

/// Red and blue halves flashing in turn.
final class Police: Effect {
    var t = 0
    func next() -> Grid {
        let side = (t / 12) % 2
        let on = [0, 1, 2, 4, 5, 6].contains(t % 12)
        t += 1
        let colour = side == 0 ? RGB(r: 255, g: 0, b: 0) : RGB(r: 0, g: 40, b: 255)
        return (0..<R).map { _ in (0..<C).map { c in
            on && (c < C / 2) == (side == 0) ? colour : .black
        } }
    }
}

/// Rolling blue waves with white foam on the crests.
final class Ocean: Effect {
    var t = 0.0
    func next() -> Grid {
        defer { t += 0.12 }
        return (0..<R).map { r in (0..<C).map { c in
            let x = Double(c)
            let crest = 2.5 + 1.6 * sin(x * 0.45 - t) + 0.6 * sin(x * 0.9 + t * 1.7)
            let depth = Double(r) - crest
            if depth < -0.5 { return RGB(r: 0, g: 8, b: 20) }
            if depth < 0.5 { return RGB(r: 200, g: 230, b: 255) }
            let v = max(0.25, 1 - depth / 5)
            return RGB(0, 90 * v, 255 * v)
        } }
    }
}

/// Random keys pop in random colours and fade.
final class Confetti: Effect {
    var g = blank()
    func next() -> Grid {
        g = g.map { $0.map { $0.scaled(0.85) } }
        for _ in 0..<3 { g[Int.random(in: 0..<R)][Int.random(in: 0..<C)] = hsv(rnd(0, 1)) }
        return g
    }
}

/// Fake music visualiser: bouncing bars on each column, green to red.
final class Equalizer: Effect {
    var levels = Array(repeating: 0.0, count: C)
    var t = 0.0
    func next() -> Grid {
        for c in 0..<C {
            let x = Double(c)
            let target = (0.5 + 0.5 * sin(x * 0.5 + t * 2.3) * sin(t * 1.1 + x)) * Double(R) + rnd(-0.8, 0.8)
            levels[c] = levels[c] * 0.6 + target * 0.4
        }
        t += 0.12
        var g = blank()
        for c in 0..<C {
            let height = Int(max(0, levels[c]).rounded())
            for h in 0..<min(height, R) {
                g[R - 1 - h][c] = h < 3 ? RGB(r: 0, g: 255, b: 40) : h < 5 ? RGB(r: 255, g: 200, b: 0) : RGB(r: 255, g: 0, b: 0)
            }
        }
        return g
    }
}

/// Conway's Game of Life; reseeds when the board stalls.
final class Life: Effect {
    var board: [[Bool]] = []
    var history: [[[Bool]]] = []
    var hue = 0.0, t = 0

    init() { reseed() }

    func reseed() {
        board = (0..<R).map { _ in (0..<C).map { _ in rnd(0, 1) < 0.35 } }
        history = []
        hue = rnd(0, 1)
    }

    func next() -> Grid {
        if t % 6 == 0 {
            var nxt = board
            for r in 0..<R {
                for c in 0..<C {
                    var n = 0
                    for dr in -1...1 { for dc in -1...1 where dr != 0 || dc != 0 {
                        if board[(r + dr + R) % R][(c + dc + C) % C] { n += 1 }
                    } }
                    nxt[r][c] = n == 3 || (board[r][c] && n == 2)
                }
            }
            if history.contains(nxt) || !nxt.joined().contains(true) {
                reseed()
            } else {
                history = Array((history + [nxt]).suffix(6))
                board = nxt
            }
        }
        t += 1
        return board.map { row in row.enumerated().map { c, alive in
            alive ? hsv(hue + Double(c) / 60, 0.8, 1) : RGB(r: 0, g: 0, b: 6)
        } }
    }
}

/// Lava lamp: slow blobs that merge and split, orange on deep purple.
final class Lava: Effect {
    struct Blob { var x, y, dx, dy, size: Double }
    var blobs = (0..<4).map { _ in
        Blob(x: rnd(0, Double(C)), y: rnd(0, Double(R)), dx: rnd(-0.12, 0.12), dy: rnd(-0.05, 0.05), size: rnd(2.5, 4))
    }
    func next() -> Grid {
        for i in blobs.indices {
            blobs[i].x += blobs[i].dx
            blobs[i].y += blobs[i].dy
            if blobs[i].x < 0 || blobs[i].x >= Double(C) { blobs[i].dx = -blobs[i].dx }
            if blobs[i].y < 0 || blobs[i].y >= Double(R) { blobs[i].dy = -blobs[i].dy }
        }
        return (0..<R).map { r in (0..<C).map { c in
            let field = blobs.reduce(0.0) { sum, b in
                let dx = Double(c) - b.x, dy = (Double(r) - b.y) * 2
                return sum + b.size * b.size / (dx * dx + dy * dy + 0.5)
            }
            let v = min(1, max(0, (field - 0.7) * 1.5))
            return RGB(40 + 215 * v, 10 + 140 * v * v, 60 * (1 - v))
        } }
    }
}

/// Pieces drop into the lowest gaps; full rows flash white and clear.
final class Tetris: Effect {
    static let shapes: [[(Int, Int)]] = [
        [(0, 0), (0, 1), (0, 2), (0, 3)], [(0, 0), (0, 1), (1, 0), (1, 1)],
        [(0, 1), (1, 0), (1, 1), (1, 2)], [(0, 0), (1, 0), (1, 1), (1, 2)],
        [(0, 2), (1, 0), (1, 1), (1, 2)], [(0, 1), (0, 2), (1, 0), (1, 1)],
        [(0, 0), (0, 1), (1, 1), (1, 2)],
    ]
    var board: [[RGB?]] = Array(repeating: Array(repeating: nil, count: C), count: R)
    var piece: (shape: [(Int, Int)], row: Int, col: Int, colour: RGB)?
    var queued: [Grid] = []
    var tick = 0

    func fits(_ shape: [(Int, Int)], _ row: Int, _ col: Int) -> Bool {
        shape.allSatisfy { r, c in
            let rr = r + row, cc = c + col
            return rr >= 0 && rr < R && cc >= 0 && cc < C && board[rr][cc] == nil
        }
    }

    func render() -> Grid { board.map { $0.map { $0 ?? .black } } }

    func next() -> Grid {
        if !queued.isEmpty { return queued.removeFirst() }
        if piece == nil {
            let shape = Self.shapes.randomElement()!
            let width = shape.map { $0.1 }.max()! + 1
            // Pick the column whose landing spot is lowest, so rows actually fill up.
            var best: (score: Double, col: Int)?
            for col in 0...(C - width) {
                var land = -1
                while fits(shape, land + 1, col) { land += 1 }
                let score = Double(land) + rnd(0, 1)
                if land >= 0 && (best == nil || score > best!.score) { best = (score, col) }
            }
            guard let best else {
                board = Array(repeating: Array(repeating: nil, count: C), count: R)
                return render()
            }
            piece = (shape, 0, best.col, hsv(rnd(0, 1)))
        }
        if tick % 3 == 0, let p = piece {
            if fits(p.shape, p.row + 1, p.col) {
                piece!.row += 1
            } else {
                for (r, c) in p.shape { board[r + p.row][c + p.col] = p.colour }
                piece = nil
                let full = (0..<R).filter { r in board[r].allSatisfy { $0 != nil } }
                if !full.isEmpty {
                    var flash = render()
                    for r in full { flash[r] = Array(repeating: RGB(r: 255, g: 255, b: 255), count: C) }
                    queued = Array(repeating: flash, count: 6)
                    board = full.map { _ in Array(repeating: nil, count: C) } + (0..<R).filter { !full.contains($0) }.map { board[$0] }
                }
            }
        }
        tick += 1
        var g = render()
        if let p = piece { for (r, c) in p.shape { g[r + p.row][c + p.col] = p.colour } }
        return g
    }
}

/// Two paddles that occasionally miss; the losing side flashes red.
final class Pong: Effect {
    var x = 11.0, y = 2.5, dx = 0.45, dy = 0.22
    var paddles = [2.5, 2.5]
    var queued: [Grid] = []

    func next() -> Grid {
        if !queued.isEmpty { return queued.removeFirst() }
        x += dx
        y += dy
        if y < 0 || y > Double(R - 1) {
            dy = -dy
            y = max(0, min(Double(R - 1), y))
        }
        for (i, px) in [(0, 1.0), (1, Double(C - 2))] {
            // Each paddle chases the ball a bit too slowly to be perfect.
            paddles[i] += max(-0.18, min(0.18, y - paddles[i]))
            let approaching = i == 0 ? dx < 0 : dx > 0
            if approaching && abs(x - px) < 0.5 {
                if abs(y - paddles[i]) <= 1.2 {
                    dx = -dx
                    dy += rnd(-0.08, 0.08)
                } else {
                    let side = i == 0 ? 0..<3 : (C - 3)..<C
                    let lit = (0..<R).map { _ in (0..<C).map { side.contains($0) ? RGB(r: 255, g: 0, b: 0) : .black } }
                    queued = (0..<8).map { $0 % 2 == 0 ? lit : blank() }
                    x = 11; y = rnd(1, 4); dx = i == 0 ? 0.45 : -0.45
                    return queued.removeFirst()
                }
            }
        }
        var g = blank()
        for c in 0..<C {
            g[0][c] = RGB(r: 10, g: 10, b: 25)
            g[R - 1][c] = RGB(r: 10, g: 10, b: 25)
        }
        for r in 0..<R {
            if abs(Double(r) - paddles[0]) <= 1 { g[r][0] = RGB(r: 0, g: 200, b: 255) }
            if abs(Double(r) - paddles[1]) <= 1 { g[r][C - 1] = RGB(r: 255, g: 0, b: 200) }
        }
        g[Int(y.rounded())][max(0, min(C - 1, Int(x.rounded())))] = RGB(r: 255, g: 255, b: 255)
        return g
    }
}

/// Rockets climb from the space bar and burst into falling sparks.
final class Fireworks: Effect {
    struct Rocket { var x, y, top, hue: Double }
    struct Spark { var x, y, vx, vy, life, hue: Double }
    var rockets: [Rocket] = []
    var sparks: [Spark] = []

    func next() -> Grid {
        if rnd(0, 1) < 0.06 {
            rockets.append(Rocket(x: rnd(2, Double(C - 3)), y: Double(R - 1), top: rnd(0, 2), hue: rnd(0, 1)))
        }
        var g = blank()
        var stillFlying: [Rocket] = []
        for var rk in rockets {
            rk.y -= 0.35
            if rk.y <= rk.top {
                for _ in 0..<14 {
                    let a = rnd(0, 2 * .pi), sp = rnd(0.15, 0.5)
                    sparks.append(Spark(x: rk.x, y: rk.y, vx: cos(a) * sp, vy: sin(a) * sp * 0.5, life: 1, hue: rk.hue))
                }
            } else {
                g[Int(rk.y.rounded())][Int(rk.x.rounded())] = RGB(r: 255, g: 200, b: 120)
                stillFlying.append(rk)
            }
        }
        rockets = stillFlying
        var alive: [Spark] = []
        for var s in sparks {
            s.x += s.vx; s.y += s.vy; s.vy += 0.03; s.life *= 0.9
            let r = Int(s.y.rounded()), c = Int(s.x.rounded())
            guard s.life >= 0.05, r >= 0, r < R, c >= 0, c < C else { continue }
            let col = hsv(s.hue, 0.7, s.life), cur = g[r][c]
            g[r][c] = RGB(r: max(cur.r, col.r), g: max(cur.g, col.g), b: max(cur.b, col.b))
            alive.append(s)
        }
        sparks = alive
        return g
    }
}

/// Dark rain with lightning that forks down the keys and lights the sky.
final class Storm: Effect {
    var drops = (0..<10).map { _ in (c: Int.random(in: 0..<C), y: rnd(0, Double(R))) }
    var flash = 0.0
    var bolt: [(Int, Int)] = []

    func next() -> Grid {
        if flash < 0.05 && rnd(0, 1) < 0.025 {
            flash = 1
            var c = Int.random(in: 3..<(C - 3))
            bolt = (0..<R).map { r in
                defer { c = max(0, min(C - 1, c + Int.random(in: -1...1))) }
                return (r, c)
            }
        }
        let sky = 70 * flash
        var g = blank(RGB(sky, sky, 15 + 90 * flash))
        for i in drops.indices {
            drops[i].y += 0.3
            if drops[i].y >= Double(R) { drops[i] = (Int.random(in: 0..<C), 0) }
            g[Int(drops[i].y)][drops[i].c] = RGB(r: 40, g: 70, b: 160)
        }
        if flash > 0.3 { for (r, c) in bolt { g[r][c] = RGB(r: 255, g: 255, b: 255) } }
        flash *= 0.8
        return g
    }
}

/// The current time in pixel digits; the top row fills up as the minute passes.
final class Clock: Effect {
    static let digits: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
    ]
    var t = 0

    func next() -> Grid {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        var g = blank(RGB(r: 0, g: 0, b: 8))
        for i in 0..<Int((Double(now.second!) / 60 * Double(C)).rounded()) { g[0][i] = RGB(r: 30, g: 30, b: 60) }
        let text = String(format: "%02d%02d", now.hour!, now.minute!)
        for (i, ch) in text.enumerated() {
            let left = 2 + i * 4 + (i >= 2 ? 1 : 0)
            for (r, line) in Self.digits[ch]!.enumerated() {
                for (dc, bit) in line.enumerated() where bit == "1" {
                    g[r + 1][left + dc] = hsv(Double(t) / 400 + Double(left + dc) / 60, 0.8, 1)
                }
            }
        }
        if now.second! % 2 == 0 {
            g[2][10] = RGB(r: 255, g: 255, b: 255)
            g[4][10] = RGB(r: 255, g: 255, b: 255)
        }
        t += 1
        return g
    }
}

/// Live CPU usage of this Mac as a bar graph that scrolls in from the right.
final class CPU: Effect {
    var history = Array(repeating: 0.0, count: C)
    var lastSample = Date.distantPast
    var lastTicks: (busy: Double, total: Double)?

    func ticks() -> (busy: Double, total: Double)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0), system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    func next() -> Grid {
        if Date().timeIntervalSince(lastSample) > 1, let now = ticks() {
            if let last = lastTicks, now.total > last.total {
                history = Array(history.dropFirst()) + [min(1, (now.busy - last.busy) / (now.total - last.total))]
            }
            lastTicks = now
            lastSample = Date()
        }
        var g = blank()
        for (c, load) in history.enumerated() {
            let height = load * Double(R)
            for h in 0..<R {
                let v = max(0, min(1, height - Double(h)))
                if v > 0 { g[R - 1 - h][c] = hsv(0.33 * (1 - load), 1, v) }
            }
        }
        return g
    }
}

/// Warm flickering glow, brightest low in the middle like a flame.
final class Candle: Effect {
    var flicker = 1.0
    func next() -> Grid {
        flicker = flicker * 0.7 + rnd(0.55, 1) * 0.3
        return (0..<R).map { r in (0..<C).map { c in
            let d = hypot(Double(c - 11) / 11, Double(R - 1 - r) / 7)
            let v = max(0.04, (1 - d) * flicker + rnd(-0.03, 0.03))
            return RGB(255 * min(1, v * 1.2), 110 * v * v, 10 * v)
        } }
    }
}

/// A rotating double helix along the keyboard, with rungs between the strands.
final class DNA: Effect {
    var t = 0.0
    func next() -> Grid {
        var g = blank()
        for c in 0..<C {
            let a = Double(c) * 0.55 + t
            let y1 = Int((2.5 + 2.5 * sin(a)).rounded()), y2 = Int((2.5 - 2.5 * sin(a)).rounded())
            let front = cos(a) > 0
            if c % 2 == 0, min(y1, y2) + 1 < max(y1, y2) {
                for r in (min(y1, y2) + 1)..<max(y1, y2) { g[r][c] = RGB(r: 40, g: 40, b: 70) }
            }
            g[y1][c] = front ? RGB(r: 0, g: 220, b: 255) : RGB(r: 0, g: 70, b: 90)
            g[y2][c] = front ? RGB(r: 90, g: 20, b: 60) : RGB(r: 255, g: 60, b: 160)
        }
        t += 0.12
        return g
    }
}
