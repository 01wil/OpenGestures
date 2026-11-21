// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Config
import Foundation
import Model
import Recognizer

/// One recogniser per trackpad, so two devices' frames never mix into one gesture.
/// Called from MultitouchSupport threads; the lock serialises access.
public final class GesturePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var tuning: Tuning
    private var recognizers: [Int: GestureRecognizer] = [:]

    public init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    public func setSensitivity(_ sensitivity: Double) { update { $0.sensitivity = sensitivity } }

    /// On while any binding shows the switcher preview, which needs the movement after a swipe fired.
    public func setFollowsSwipes(_ follows: Bool) { update { $0.followsSwipes = follows } }

    private func update(_ change: (inout Tuning) -> Void) {
        lock.withLock {
            change(&tuning)
            for r in recognizers.values { r.tuning = tuning }
        }
    }

    public func process(device: Int, frame: TouchFrame) -> [GestureEvent] {
        lock.withLock {
            if let r = recognizers[device] { return r.process(frame) }
            let r = GestureRecognizer(tuning: tuning)
            recognizers[device] = r
            return r.process(frame)
        }
    }

    /// Drops all state, e.g. after the device list changed.
    public func reset() {
        lock.withLock { recognizers = [:] }
    }
}

public enum Dispatch: Equatable, Sendable {
    case run(Action)
    case adjust(AdjustTarget, Double)
    /// Open the window switcher; `older` for "previous window".
    case switcher(older: Bool)
}

public enum Dispatcher {
    /// What to do for a recognised gesture. A continuous event only drives an adjust binding and a discrete
    /// one never does; the editor warns about such bindings, here they are simply ignored. A window action
    /// with preview opens the switcher when a swipe fired it; anything else has no movement to follow.
    /// Follow-up events of a swipe (`.changed`, `.ended`) belong to the switcher and never dispatch.
    public static func dispatch(_ event: GestureEvent, bindings: [Binding], modifiers: Modifiers, app: String?) -> Dispatch? {
        guard event.phase == .began,
              let binding = BindingResolver.resolve(bindings, gesture: event.gesture, modifiers: modifiers, app: app) else { return nil }
        switch (binding.action, event.delta, event.gesture) {
        case let (.adjust(target), delta?, _): return .adjust(target, delta)
        case (.adjust, nil, _), (_, _?, _): return nil
        case (.previousWindow(true), nil, .swipe): return .switcher(older: true)
        case (.nextWindow(true), nil, .swipe): return .switcher(older: false)
        case let (action, nil, _): return .run(action)
        }
    }
}

extension Modifiers {
    public init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
    }
}
