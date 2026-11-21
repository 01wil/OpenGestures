// SPDX-License-Identifier: GPL-3.0-or-later

/// A recognised trackpad gesture. Its `id` is the stable, human-readable form used in the config file.
public enum Gesture: Hashable, Sendable {
    case swipe(fingers: Int, direction: Direction)
    case tap(fingers: Int)
    case pinch(fingers: Int, direction: PinchDirection)
    case rotate(Rotation)
    /// One finger rests, another taps on the given side of it.
    case tipTap(side: Side)
    /// One finger starts at an edge and swipes inward.
    case edgeSwipe(edge: Edge)
    /// One finger taps inside a corner.
    case cornerTap(corner: Corner)
    /// One finger slides along an edge; continuous, reports a delta while moving.
    case edgeSlide(edge: Edge)

    public enum Direction: String, Sendable, CaseIterable { case left, right, up, down }
    public enum PinchDirection: String, Sendable, CaseIterable { case pinchIn = "in", pinchOut = "out" }
    public enum Rotation: String, Sendable, CaseIterable { case clockwise = "cw", counterClockwise = "ccw" }
    public enum Side: String, Sendable, CaseIterable { case left, right }
    public enum Edge: String, Sendable, CaseIterable { case left, right, top, bottom }
    public enum Corner: String, Sendable, CaseIterable {
        case topLeft = "topleft", topRight = "topright", bottomLeft = "bottomleft", bottomRight = "bottomright"
    }

    public static let swipeFingers = 2...5
    public static let tapFingers = 1...5
    public static let pinchFingers = 2...5

    public var isContinuous: Bool {
        if case .edgeSlide = self { return true }
        return false
    }

    public var id: String {
        switch self {
        case let .swipe(n, d): "swipe.\(n).\(d.rawValue)"
        case let .tap(n): "tap.\(n)"
        case let .pinch(n, d): "pinch.\(n).\(d.rawValue)"
        case let .rotate(r): "rotate.\(r.rawValue)"
        case let .tipTap(s): "tiptap.\(s.rawValue)"
        case let .edgeSwipe(e): "edgeswipe.\(e.rawValue)"
        case let .cornerTap(c): "cornertap.\(c.rawValue)"
        case let .edgeSlide(e): "edgeslide.\(e.rawValue)"
        }
    }

    public init?(id: String) {
        let p = id.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        func fingers(_ s: String, _ range: ClosedRange<Int>) -> Int? {
            Int(s).flatMap { range.contains($0) ? $0 : nil }
        }
        switch (p.first, p.count) {
        case ("swipe", 3):
            guard let n = fingers(p[1], Self.swipeFingers), let d = Direction(rawValue: p[2]) else { return nil }
            self = .swipe(fingers: n, direction: d)
        case ("tap", 2):
            guard let n = fingers(p[1], Self.tapFingers) else { return nil }
            self = .tap(fingers: n)
        case ("pinch", 3):
            guard let n = fingers(p[1], Self.pinchFingers), let d = PinchDirection(rawValue: p[2]) else { return nil }
            self = .pinch(fingers: n, direction: d)
        case ("rotate", 2):
            guard let r = Rotation(rawValue: p[1]) else { return nil }
            self = .rotate(r)
        case ("tiptap", 2):
            guard let s = Side(rawValue: p[1]) else { return nil }
            self = .tipTap(side: s)
        case ("edgeswipe", 2):
            guard let e = Edge(rawValue: p[1]) else { return nil }
            self = .edgeSwipe(edge: e)
        case ("cornertap", 2):
            guard let c = Corner(rawValue: p[1]) else { return nil }
            self = .cornerTap(corner: c)
        case ("edgeslide", 2):
            guard let e = Edge(rawValue: p[1]) else { return nil }
            self = .edgeSlide(edge: e)
        default:
            return nil
        }
    }
}

extension Gesture: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let g = Gesture(id: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown gesture \"\(s)\"")
        }
        self = g
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}

/// What the recogniser emits. Discrete gestures fire once with `delta == nil`;
/// continuous ones fire repeatedly with a signed delta (positive = right/up).
/// When the recogniser follows swipes, a fired swipe is followed by `.changed` events carrying the movement
/// along its axis since the last one (positive = right/up) and one `.ended` event when the fingers lift.
public struct GestureEvent: Equatable, Sendable {
    public enum Phase: Sendable { case began, changed, ended }

    public var gesture: Gesture
    public var delta: Double?
    public var phase: Phase

    public init(_ gesture: Gesture, delta: Double? = nil, phase: Phase = .began) {
        self.gesture = gesture
        self.delta = delta
        self.phase = phase
    }
}
