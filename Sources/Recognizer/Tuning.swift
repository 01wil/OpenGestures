// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Recogniser thresholds. Distances are in normalised trackpad units (0...1 across each axis).
public struct Tuning: Sendable, Equatable {
    /// 0 = needs big, deliberate movements; 1 = reacts to small ones. 0.5 is the default.
    public var sensitivity: Double

    /// Contacts larger than this (`Touch.size`) are treated as a resting palm or thumb and ignored.
    public var palmSize: Float

    /// Keep reporting a swipe's movement after it fired, until the fingers lift (see `GestureEvent.Phase`).
    public var followsSwipes: Bool

    public init(sensitivity: Double = 0.5, palmSize: Float = 2, followsSwipes: Bool = false) {
        self.sensitivity = sensitivity
        self.palmSize = palmSize
        self.followsSwipes = followsSwipes
    }

    /// 2 at sensitivity 0, 1 at 0.5, 0.5 at 1; multiplies every movement threshold.
    var scale: Double { pow(2, 1 - 2 * min(max(sensitivity, 0), 1)) }

    var swipeDistance: Double { 0.10 * scale }
    /// Units per second over the last `speedWindow`; filters slow drags.
    var swipeMinSpeed: Double { 0.4 * scale }
    let speedWindow = 0.1
    /// The major axis must be this many times the minor one.
    let dominance = 1.5

    /// Change of the mean finger distance to the centroid, as a log ratio (ln 1.25: 25% wider or 20% narrower).
    var pinchLogRatio: Double { log(1.25) * scale }
    /// Radians; two-finger rotation only.
    var rotateAngle: Double { 0.35 * scale }
    /// Below this mean spread, pinch and rotation are too noisy to measure.
    let minSpread = 0.03

    let tapMaxDuration = 0.25
    /// Shorter contacts are sensor noise.
    let tapMinDuration = 0.02
    let tapMaxMove = 0.03
    let cornerZone = 0.10

    /// A TipTap's resting finger has been down this long, moving at most `restMaxMove`, when the tapping finger lands.
    let restTime = 0.15
    let restMaxMove = 0.02

    /// Edge gestures start this close to an edge.
    let edgeZone = 0.05
    var edgeSwipeDistance: Double { 0.08 * scale }
    /// Movement along the edge that turns a touch into an edge slide.
    var edgeSlideStart: Double { 0.03 * scale }
}
