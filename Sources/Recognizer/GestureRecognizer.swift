// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model
import os

private let logger = Logger(subsystem: "io.github.opengestures.OpenGestures", category: "recognizer")

/// Turns a stream of `TouchFrame`s into `GestureEvent`s. Not thread-safe; feed it from one queue.
public final class GestureRecognizer {
    public var tuning: Tuning
    private static let maxMissingFrames = 2

    private struct Track {
        var start: Point
        var down: Double
        var travel = 0.0
    }

    /// From the first finger down until all fingers are lifted.
    private struct Session {
        var start: Double
        var last: Double
        var maxCount = 0
        /// A discrete gesture fired; nothing else fires until all fingers lift.
        var done = false
        /// Every finger seen in this session, including lifted ones.
        var tracks: [Int: Track] = [:]
        /// Finger positions when the set of fingers last changed; movement is measured from here
        /// so a finger landing or lifting does not look like a jump of the centroid.
        var baseline: [Int: Point] = [:]
        var history: [(t: Double, offset: Point)] = []
        /// A second finger landed next to a resting one.
        var tip: (rest: Int, tapper: Int, landed: Double)?
        var tipTaps = 0
        /// The edge a one-finger slide runs along, and how far along it has been reported so far.
        var slide: (edge: Gesture.Edge, reported: Double)?
        /// The swipe being followed after it fired.
        var follow: (fingers: Int, direction: Gesture.Direction)?
    }

    private var positions: [Int: Point] = [:]
    private var palms: Set<Int> = []
    /// Consecutive frames each finger has been absent while others stayed down.
    private var missing: [Int: Int] = [:]
    private var session: Session?

    public init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    public func reset() {
        positions = [:]
        palms = []
        missing = [:]
        session = nil
    }

    public func process(_ frame: TouchFrame) -> [GestureEvent] {
        let t = frame.timestamp
        let contacts = frame.touches.filter(\.isTouching)
        // A contact that was ever palm-sized stays ignored for its lifetime.
        palms = palms.intersection(contacts.map(\.id)).union(contacts.filter { $0.size > tuning.palmSize }.map(\.id))
        var current = Dictionary(
            contacts.filter { !palms.contains($0.id) }.map { ($0.id, Point(x: Double($0.x), y: Double($0.y))) },
            uniquingKeysWith: { a, _ in a })
        // A finger that drops out for a frame or two is still there, at its last position.
        if current.isEmpty { missing = [:] } else {
            let seen = current
            missing = missing.filter { seen[$0.key] == nil }
            for (id, p) in positions where seen[id] == nil {
                let n = (missing[id] ?? 0) + 1
                if n <= Self.maxMissingFrames { missing[id] = n; current[id] = p } else { missing[id] = nil }
            }
        }
        // While following, a frame with contacts but none touching is the hand lightening, not lifting.
        if current.isEmpty, let s = session, s.follow != nil, !frame.touches.isEmpty, t - s.last < tuning.followGrace {
            return []
        }
        let landed = Set(current.keys).subtracting(positions.keys)
        let setChanged = !landed.isEmpty || current.count != positions.count
        let previous = positions
        positions = current

        guard !current.isEmpty else {
            defer { session = nil }
            if let f = session?.follow {
                logger.info("follow ended: \(frame.touches.isEmpty ? "all fingers lifted" : "no finger touching for \(self.tuning.followGrace) s", privacy: .public)")
                return [GestureEvent(.swipe(fingers: f.fingers, direction: f.direction), phase: .ended)]
            }
            return session.flatMap(ended).map { [GestureEvent($0)] } ?? []
        }
        var s = session ?? Session(start: t, last: t)
        var events: [GestureEvent] = []
        if let tip = s.tip, current[tip.tapper] == nil {
            s.tip = nil
            if let side = tipTap(s, tip, t) {
                s.tipTaps += 1
                events.append(GestureEvent(.tipTap(side: side)))
            }
        }
        s.last = t
        for (id, p) in current {
            var track = s.tracks[id] ?? Track(start: p, down: t)
            track.travel = max(track.travel, (p - track.start).length)
            s.tracks[id] = track
        }
        if setChanged {
            s.baseline = current
            s.history = []
            s.tip = nil
            if landed.count == 1, let tapper = landed.first, previous.count == 1, let rest = previous.keys.first,
               current[rest] != nil, let r = s.tracks[rest], t - r.down >= tuning.restTime, r.travel <= tuning.restMaxMove {
                s.tip = (rest, tapper, t)
            }
        }
        s.maxCount = max(s.maxCount, current.count)
        if s.maxCount == 1, let (id, p) = current.first, let track = s.tracks[id] {
            events += oneFinger(&s, track, p)
        }
        if let f = s.follow, let delta = Self.movement(along: f.direction, from: previous, to: current), delta != 0 {
            events.append(GestureEvent(.swipe(fingers: f.fingers, direction: f.direction), delta: delta, phase: .changed))
        }
        if !s.done, current.count >= 2, current.count == s.maxCount, let g = multiFinger(&s, t) {
            s.done = true
            if tuning.followsSwipes, case let .swipe(n, d) = g { s.follow = (n, d) }
            events.append(GestureEvent(g))
        }
        session = s
        return events
    }

    /// Mean movement of the fingers present in both frames, along the swipe's axis (positive = right/up),
    /// so a finger landing or lifting does not move the result.
    private static func movement(along direction: Gesture.Direction, from a: [Int: Point], to b: [Int: Point]) -> Double? {
        let moves = b.compactMap { id, p in a[id].map { p - $0 } }
        guard !moves.isEmpty else { return nil }
        let d = moves.reduce(Point.zero, +) / Double(moves.count)
        return direction == .left || direction == .right ? d.x : d.y
    }

    private func ended(_ s: Session) -> Gesture? {
        let duration = s.last - s.start
        guard !s.done, s.tipTaps == 0, (tuning.tapMinDuration...tuning.tapMaxDuration).contains(duration),
              s.tracks.values.allSatisfy({ $0.travel <= tuning.tapMaxMove }) else { return nil }
        if s.maxCount == 1, let p = s.tracks.values.first?.start, let c = corner(p) { return .cornerTap(corner: c) }
        return .tap(fingers: s.maxCount)
    }

    private func oneFinger(_ s: inout Session, _ track: Track, _ p: Point) -> [GestureEvent] {
        if let slide = s.slide {
            let along = Self.along(slide.edge, p - track.start)
            s.slide?.reported = along
            return along == slide.reported ? [] : [GestureEvent(.edgeSlide(edge: slide.edge), delta: along - slide.reported)]
        }
        guard !s.done, let edge = edge(track.start) else { return [] }
        let d = p - track.start
        let inward = Self.inward(edge, d), along = Self.along(edge, d)
        if inward >= tuning.edgeSwipeDistance, inward >= tuning.dominance * abs(along) {
            s.done = true
            return [GestureEvent(.edgeSwipe(edge: edge))]
        }
        if abs(along) >= tuning.edgeSlideStart, abs(along) >= tuning.dominance * max(inward, 0) {
            s.done = true
            s.slide = (edge, along)
            return [GestureEvent(.edgeSlide(edge: edge), delta: along)]
        }
        return []
    }

    /// The nearest edge within `edgeZone`.
    private func edge(_ p: Point) -> Gesture.Edge? {
        let distances: [(Gesture.Edge, Double)] = [(.left, p.x), (.right, 1 - p.x), (.bottom, p.y), (.top, 1 - p.y)]
        return distances.filter { $0.1 <= tuning.edgeZone }.min { $0.1 < $1.1 }?.0
    }

    private static func inward(_ edge: Gesture.Edge, _ d: Point) -> Double {
        switch edge {
        case .left: d.x
        case .right: -d.x
        case .bottom: d.y
        case .top: -d.y
        }
    }

    /// Positive is up along the left and right edges, right along the top and bottom ones.
    private static func along(_ edge: Gesture.Edge, _ d: Point) -> Double {
        switch edge {
        case .left, .right: d.y
        case .top, .bottom: d.x
        }
    }

    private func tipTap(_ s: Session, _ tip: (rest: Int, tapper: Int, landed: Double), _ t: Double) -> Gesture.Side? {
        guard !s.done, let rest = s.tracks[tip.rest], let tapper = s.tracks[tip.tapper], let restNow = positions[tip.rest],
              t - tip.landed <= tuning.tapMaxDuration, tapper.travel <= tuning.tapMaxMove,
              rest.travel <= tuning.restMaxMove else { return nil }
        return tapper.start.x < restNow.x ? .left : .right
    }

    private func corner(_ p: Point) -> Gesture.Corner? {
        let z = tuning.cornerZone
        switch (p.x <= z, p.x >= 1 - z, p.y <= z, p.y >= 1 - z) {
        case (true, _, _, true): return .topLeft
        case (_, true, _, true): return .topRight
        case (true, _, true, _): return .bottomLeft
        case (_, true, true, _): return .bottomRight
        default: return nil
        }
    }

    /// Swipe, pinch and rotation each get a score of signal / threshold; the first to reach 1 wins,
    /// the larger one if several cross in the same frame.
    private func multiFinger(_ s: inout Session, _ t: Double) -> Gesture? {
        let ids = positions.keys.sorted()
        let now = ids.map { positions[$0]! }
        let base = ids.map { s.baseline[$0] ?? positions[$0]! }
        let offset = zip(now, base).reduce(Point.zero) { $0 + ($1.0 - $1.1) } / Double(ids.count)
        s.history.append((t, offset))
        s.history.removeAll { t - $0.t > tuning.speedWindow }

        var candidates: [(Gesture, Double)] = []
        if let old = s.history.first, t > old.t, (offset - old.offset).length / (t - old.t) >= tuning.swipeMinSpeed,
           let direction = dominantDirection(offset) {
            candidates.append((.swipe(fingers: ids.count, direction: direction), offset.length / tuning.swipeDistance))
        }
        let spreadNow = spread(now), spreadBase = spread(base)
        if spreadBase >= tuning.minSpread, spreadNow > 0 {
            let r = log(spreadNow / spreadBase)
            candidates.append((.pinch(fingers: ids.count, direction: r < 0 ? .pinchIn : .pinchOut), abs(r) / tuning.pinchLogRatio))
            if ids.count == 2 {
                let a = remainder(angle(now) - angle(base), 2 * .pi)
                candidates.append((.rotate(a < 0 ? .clockwise : .counterClockwise), abs(a) / tuning.rotateAngle))
            }
        }
        return candidates.filter { $0.1 >= 1 }.max { $0.1 < $1.1 }?.0
    }

    private func spread(_ points: [Point]) -> Double {
        let c = points.reduce(Point.zero, +) / Double(points.count)
        return points.reduce(0) { $0 + ($1 - c).length } / Double(points.count)
    }

    private func angle(_ p: [Point]) -> Double { atan2(p[1].y - p[0].y, p[1].x - p[0].x) }

    private func dominantDirection(_ d: Point) -> Gesture.Direction? {
        if abs(d.x) >= tuning.dominance * abs(d.y) { return d.x < 0 ? .left : .right }
        if abs(d.y) >= tuning.dominance * abs(d.x) { return d.y < 0 ? .down : .up }
        return nil
    }
}

struct Point: Equatable {
    var x: Double
    var y: Double
    static let zero = Point(x: 0, y: 0)
    static func + (a: Point, b: Point) -> Point { Point(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Point, b: Point) -> Point { Point(x: a.x - b.x, y: a.y - b.y) }
    static func / (a: Point, k: Double) -> Point { Point(x: a.x / k, y: a.y / k) }
    var length: Double { (x * x + y * y).squareRoot() }
}
