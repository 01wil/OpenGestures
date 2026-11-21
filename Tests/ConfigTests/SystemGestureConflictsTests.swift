// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Model
@testable import Config

@Suite struct SystemGestureConflictsTests {
    func find(_ bindings: [Binding], builtIn: [String: Any] = [:], bluetooth: [String: Any] = [:]) -> [SystemGestureConflict] {
        SystemGestureConflicts.find(bindings, builtInTrackpad: builtIn, bluetoothTrackpad: bluetooth)
    }

    @Test func fourFingerHorizontalSwipeConflictsWithDefaults() {
        let c = find(Configuration.default.bindings, builtIn: ["TrackpadFourFingerHorizSwipeGesture": 2])
        #expect(c.count == 1)
        #expect(c.first?.bindingIDs == Configuration.default.bindings.map(\.id))
        #expect(c.first?.message == "4-finger swipe left/right is also used by macOS to switch between full-screen apps and desktops (System Settings › Trackpad › More Gestures).")
    }

    @Test func noConflictWhenSystemGestureIsOffOrMissing() {
        let b = Configuration.default.bindings
        #expect(find(b, builtIn: ["TrackpadFourFingerHorizSwipeGesture": 0]).isEmpty)
        #expect(find(b).isEmpty)
    }

    @Test func bluetoothTrackpadAlsoCounts() {
        let c = find(Configuration.default.bindings, bluetooth: ["TrackpadFourFingerHorizSwipeGesture": 2])
        #expect(c.count == 1)
    }

    @Test func disabledBindingsDoNotConflict() {
        let b = Binding(gesture: .swipe(fingers: 4, direction: .left), action: .nextWindow, enabled: false)
        #expect(find([b], builtIn: ["TrackpadFourFingerHorizSwipeGesture": 2]).isEmpty)
    }

    @Test func otherGesturesMapToTheirKeys() {
        func conflict(_ g: Gesture, _ key: String, _ value: Int = 2) -> [SystemGestureConflict] {
            find([Binding(gesture: g, action: .nextWindow)], builtIn: [key: value])
        }
        #expect(conflict(.swipe(fingers: 4, direction: .up), "TrackpadFourFingerVertSwipeGesture").count == 1)
        #expect(conflict(.swipe(fingers: 3, direction: .left), "TrackpadThreeFingerHorizSwipeGesture", 1).count == 1)
        #expect(conflict(.swipe(fingers: 3, direction: .down), "TrackpadThreeFingerVertSwipeGesture").count == 1)
        #expect(conflict(.swipe(fingers: 3, direction: .left), "TrackpadThreeFingerDrag", 1).first?.message.contains("three-finger drag") == true)
        #expect(conflict(.pinch(fingers: 4, direction: .pinchIn), "TrackpadFourFingerPinchGesture").count == 1)
        #expect(conflict(.pinch(fingers: 5, direction: .pinchOut), "TrackpadFiveFingerPinchGesture").count == 1)
        #expect(conflict(.tap(fingers: 3), "TrackpadThreeFingerTapGesture").count == 1)
        #expect(conflict(.edgeSwipe(edge: .right), "TrackpadTwoFingerFromRightEdgeSwipeGesture", 3).count == 1)
    }

    @Test func unrelatedGesturesNeverConflict() {
        let all = ["TrackpadFourFingerHorizSwipeGesture", "TrackpadFourFingerVertSwipeGesture", "TrackpadFourFingerPinchGesture",
                   "TrackpadThreeFingerDrag", "TrackpadThreeFingerTapGesture"]
        let prefs = Dictionary(uniqueKeysWithValues: all.map { ($0, 2 as Any) })
        let b = [Gesture.swipe(fingers: 2, direction: .left), .tap(fingers: 2), .rotate(.clockwise), .cornerTap(corner: .topLeft)]
            .map { Binding(gesture: $0, action: .nextWindow) }
        #expect(find(b, builtIn: prefs).isEmpty)
    }

    @Test func readingRealPreferencesDoesNotCrash() {
        _ = SystemGestureConflicts.findOnThisMac(Configuration.default.bindings)
    }
}
