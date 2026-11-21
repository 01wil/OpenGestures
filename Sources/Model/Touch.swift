// SPDX-License-Identifier: GPL-3.0-or-later

/// One finger contact. Positions are normalised to 0...1 with the origin at the bottom-left of the trackpad.
public struct Touch: Equatable, Codable, Sendable {
    /// Stable for the lifetime of one contact.
    public var id: Int
    public var x: Float
    public var y: Float
    /// Normalised units per second.
    public var vx: Float
    public var vy: Float
    /// Contact size; a resting palm or thumb is noticeably larger than a fingertip.
    public var size: Float
    /// Raw MultitouchSupport state: 1 not tracking, 2 start in range, 3 hover, 4 touching, 5 lifting, 6 out of range, 7 hover end.
    public var state: Int

    public init(id: Int, x: Float, y: Float, vx: Float = 0, vy: Float = 0, size: Float = 1, state: Int = 4) {
        self.id = id
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.size = size
        self.state = state
    }

    /// True while the finger is pressed on the surface (not hovering or lifting).
    public var isTouching: Bool { state == 4 }
}

/// Every contact on one device at one instant. An empty `touches` array means all fingers lifted.
public struct TouchFrame: Equatable, Codable, Sendable {
    /// Seconds, monotonic.
    public var timestamp: Double
    public var touches: [Touch]

    public init(timestamp: Double, touches: [Touch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
