// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model

public struct SystemGestureConflict: Equatable, Sendable {
    public var bindingIDs: [Binding.ID]
    public var message: String
}

public enum SystemGestureConflicts {
    public static let builtInDomain = "com.apple.AppleMultitouchTrackpad"
    public static let bluetoothDomain = "com.apple.driver.AppleBluetoothMultitouch.trackpad"

    private struct Rule: Sendable {
        var key: String
        var matches: @Sendable (Gesture) -> Bool
        var message: String
    }

    // Keys are the ones System Settings › Trackpad writes. Values are not documented by Apple; as observed
    // here and in community references (e.g. macos-defaults.com, dotfiles gists): 0 = off, non-zero = on
    // (2 for most gestures, 1 for ThreeFingerDrag and the "swipe between pages" variant of
    // ThreeFingerHorizSwipeGesture, 3 for the right-edge swipe). So "non-zero" is treated as enabled.
    private static let moreGestures = "System Settings › Trackpad › More Gestures"
    private static let rules: [Rule] = [
        Rule(key: "TrackpadFourFingerHorizSwipeGesture",
             matches: { swipe($0, 4, [.left, .right]) },
             message: "4-finger swipe left/right is also used by macOS to switch between full-screen apps and desktops (\(moreGestures))."),
        Rule(key: "TrackpadFourFingerVertSwipeGesture",
             matches: { swipe($0, 4, [.up, .down]) },
             message: "4-finger swipe up/down is also used by macOS for Mission Control and App Exposé (\(moreGestures))."),
        Rule(key: "TrackpadThreeFingerHorizSwipeGesture",
             matches: { swipe($0, 3, [.left, .right]) },
             message: "3-finger swipe left/right is also used by macOS to switch between pages or full-screen apps (\(moreGestures))."),
        Rule(key: "TrackpadThreeFingerVertSwipeGesture",
             matches: { swipe($0, 3, [.up, .down]) },
             message: "3-finger swipe up/down is also used by macOS for Mission Control and App Exposé (\(moreGestures))."),
        Rule(key: "TrackpadThreeFingerDrag",
             matches: { swipe($0, 3, Set(Gesture.Direction.allCases)) },
             message: "3-finger swipes are also used by macOS for three-finger drag (System Settings › Accessibility › Pointer Control › Trackpad Options)."),
        Rule(key: "TrackpadFourFingerPinchGesture",
             matches: { pinch($0, 4) },
             message: "4-finger pinch is also used by macOS for Launchpad and Show Desktop (\(moreGestures))."),
        Rule(key: "TrackpadFiveFingerPinchGesture",
             // macOS starts tracking its pinch as soon as five fingers touch, so any 5-finger gesture can trip it.
             matches: { g in
                 switch g {
                 case let .swipe(n, _), let .tap(n), let .pinch(n, _): n == 5
                 default: false
                 }
             },
             message: "5-finger gestures can also trigger macOS's 5-finger pinch for Launchpad and Show Desktop. Turn it off under \(moreGestures) if they misbehave."),
        Rule(key: "TrackpadThreeFingerTapGesture",
             matches: { $0 == .tap(fingers: 3) },
             message: "3-finger tap is also used by macOS for Look up & data detectors (\(moreGestures))."),
        Rule(key: "TrackpadTwoFingerFromRightEdgeSwipeGesture",
             matches: { $0 == .edgeSwipe(edge: .right) },
             message: "Swiping in from the right edge is also used by macOS to open Notification Center (\(moreGestures))."),
    ]

    private static func swipe(_ g: Gesture, _ fingers: Int, _ directions: Set<Gesture.Direction>) -> Bool {
        if case let .swipe(n, d) = g { return n == fingers && directions.contains(d) }
        return false
    }

    private static func pinch(_ g: Gesture, _ fingers: Int) -> Bool {
        if case let .pinch(n, _) = g { return n == fingers }
        return false
    }

    /// Pure: which enabled bindings clash with a macOS gesture that is switched on in either trackpad domain.
    public static func find(_ bindings: [Binding], builtInTrackpad: [String: Any], bluetoothTrackpad: [String: Any]) -> [SystemGestureConflict] {
        let active = bindings.filter(\.enabled)
        return rules.compactMap { rule in
            let on = [builtInTrackpad, bluetoothTrackpad].contains { ($0[rule.key] as? Int ?? 0) != 0 }
            let hits = active.filter { rule.matches($0.gesture) }
            return on && !hits.isEmpty ? SystemGestureConflict(bindingIDs: hits.map(\.id), message: rule.message) : nil
        }
    }

    /// Reads the real preferences (read-only).
    public static func findOnThisMac(_ bindings: [Binding]) -> [SystemGestureConflict] {
        func read(_ domain: String) -> [String: Any] {
            UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        }
        return find(bindings, builtInTrackpad: read(builtInDomain), bluetoothTrackpad: read(bluetoothDomain))
    }
}
