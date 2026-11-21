// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model
import Recognizer

/// Synthetic touch-frame generator for recogniser tests. Deterministic: jitter comes from a seeded RNG.
enum Synth {
    struct Finger {
        var id: Int
        var down: Double
        var up: Double
        var size: Float = 1
        /// Position at absolute time t (seconds).
        var path: (Double) -> (x: Double, y: Double)
    }

    /// Renders fingers at `hz` from t = 0 until the last finger lifts, then one empty frame.
    static func render(_ fingers: [Finger], hz: Double = 90, jitter: Double = 0.002, seed: UInt64 = 1) -> [TouchFrame] {
        var rng = SplitMix(state: seed)
        let end = fingers.map(\.up).max() ?? 0
        var frames: [TouchFrame] = []
        var t = 0.0
        while t <= end + 1e-9 {
            let touches = fingers.filter { $0.down <= t + 1e-9 && t <= $0.up + 1e-9 }.map { f -> Touch in
                let p = f.path(t)
                return Touch(id: f.id,
                             x: Float(p.x + rng.jitter(jitter)), y: Float(p.y + rng.jitter(jitter)),
                             size: f.size)
            }
            frames.append(TouchFrame(timestamp: t, touches: touches))
            t += 1 / hz
        }
        frames.append(TouchFrame(timestamp: end + 1 / hz, touches: []))
        return frames
    }

    /// Finger positions in a horizontal row around (cx, cy), 0.08 apart.
    static func row(_ n: Int, cx: Double = 0.5, cy: Double = 0.45) -> [(x: Double, y: Double)] {
        (0..<n).map { i in (cx + (Double(i) - Double(n - 1) / 2) * 0.08, cy - (i == 0 && n > 1 ? 0.06 : 0)) }
    }

    static func linear(from a: (x: Double, y: Double), by d: (x: Double, y: Double), start: Double, duration: Double)
        -> (Double) -> (x: Double, y: Double) {
        { t in
            let k = min(max((t - start) / duration, 0), 1)
            return (a.x + d.x * k, a.y + d.y * k)
        }
    }

    static func vector(_ direction: Gesture.Direction, _ length: Double) -> (x: Double, y: Double) {
        switch direction {
        case .left: (-length, 0)
        case .right: (length, 0)
        case .up: (0, length)
        case .down: (0, -length)
        }
    }

    /// Fingers land 15 ms apart, rest briefly, travel `distance` in `duration`, then lift.
    static func swipe(fingers n: Int, direction: Gesture.Direction, distance: Double = 0.3, duration: Double = 0.2,
                      hz: Double = 90, seed: UInt64 = 1) -> [TouchFrame] {
        let moveStart = 0.05 + Double(n) * 0.015
        let fingers = row(n).enumerated().map { i, p in
            Finger(id: i + 1, down: Double(i) * 0.015, up: moveStart + duration + 0.03,
                   path: linear(from: p, by: vector(direction, distance), start: moveStart, duration: duration))
        }
        return render(fingers, hz: hz, seed: seed)
    }

    static func corner(_ c: Gesture.Corner, inset: Double = 0.03) -> (x: Double, y: Double) {
        switch c {
        case .topLeft: (inset, 1 - inset)
        case .topRight: (1 - inset, 1 - inset)
        case .bottomLeft: (inset, inset)
        case .bottomRight: (1 - inset, inset)
        }
    }

    /// All fingers down within 20 ms, held for `duration`, lifted together.
    static func tap(fingers n: Int, duration: Double = 0.1, at points: [(x: Double, y: Double)]? = nil,
                    drift: (x: Double, y: Double) = (0, 0), extra: [Finger] = [], seed: UInt64 = 1) -> [TouchFrame] {
        let fingers = (points ?? row(n)).enumerated().map { i, p in
            Finger(id: i + 1, down: Double(i) * 0.005, up: duration,
                   path: linear(from: p, by: drift, start: 0, duration: duration))
        }
        return render(fingers + extra, seed: seed)
    }

    /// Fingers on a circle of `radius`; over `duration` the radius is multiplied by `scale` and the circle turned by `turn` radians (counter-clockwise positive).
    static func spread(fingers n: Int, radius: Double = 0.12, scale: Double = 1, turn: Double = 0,
                       duration: Double = 0.3, seed: UInt64 = 1) -> [TouchFrame] {
        let moveStart = 0.06
        let fingers = (0..<n).map { i in
            let a0 = Double(i) * 2 * .pi / Double(n) + 0.3
            return Finger(id: i + 1, down: Double(i) * 0.01, up: moveStart + duration + 0.03) { t in
                let k = min(max((t - moveStart) / duration, 0), 1)
                let r = radius * (1 + (scale - 1) * k), a = a0 + turn * k
                return (0.5 + r * cos(a), 0.5 + r * sin(a))
            }
        }
        return render(fingers, seed: seed)
    }

    /// A large contact resting for `duration` near the bottom of the trackpad.
    static func palm(id: Int = 99, duration: Double, at p: (x: Double, y: Double) = (0.2, 0.1)) -> Finger {
        Finger(id: id, down: 0, up: duration, size: 4, path: { _ in p })
    }
}

extension [TouchFrame] {
    func shifted(by dt: Double) -> [TouchFrame] { map { TouchFrame(timestamp: $0.timestamp + dt, touches: $0.touches) } }
    func then(_ next: [TouchFrame], gap: Double = 0.1) -> [TouchFrame] { self + next.shifted(by: (last?.timestamp ?? 0) + gap) }
}

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in -amplitude...amplitude.
    mutating func jitter(_ amplitude: Double) -> Double {
        (Double(next() >> 11) / Double(1 << 53) * 2 - 1) * amplitude
    }
}

func recognize(_ frames: [TouchFrame], tuning: Tuning = .init()) -> [GestureEvent] {
    let r = GestureRecognizer(tuning: tuning)
    return frames.flatMap { r.process($0) }
}
