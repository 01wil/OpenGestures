// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Recogniser thresholds. Distances are in normalised trackpad units (0...1 across each axis).
///
/// Measured on a real trackpad (Tests/RecognizerTests/Fixtures, 2026-11-21): frames every 8 ms; fingertip
/// `size` 0.12...0.96; a resting palm touches at 1.2 and grows to 5.7, a resting thumb starts at 0.7 and passes 2
/// after 0.4 s; swipes move the centroid 0.13...0.22 in 200...320 ms with all fingers down; the lightest tap
/// touches for three frames (16 ms), taps last 16...128 ms.
public struct Tuning: Sendable, Equatable {
    /// 0 = needs big, deliberate movements; 1 = reacts to small ones. 0.5 is the default.
    public var sensitivity: Double

    /// Contacts larger than this (`Touch.size`) are treated as a resting palm or thumb and ignored.
    public var palmSize: Float

    public init(sensitivity: Double = 0.5, palmSize: Float = 2) {
        self.sensitivity = sensitivity
        self.palmSize = palmSize
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
    /// Shorter contacts are sensor noise; a light real tap touches for 16 ms.
    let tapMinDuration = 0.01
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
