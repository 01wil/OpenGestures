// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Model
import Testing
@testable import AppCore

/// Four fingers travelling 0.3 to the left over 0.2 s at 90 Hz, then lifting.
func fourFingerSwipeLeft() -> [TouchFrame] {
    var frames: [TouchFrame] = []
    var t = 0.0
    while t <= 0.32 {
        let k = min(max((t - 0.08) / 0.2, 0), 1)
        frames.append(TouchFrame(timestamp: t, touches: (0..<4).map { i in
            Touch(id: i + 1, x: Float(0.38 + Double(i) * 0.08 - 0.3 * k), y: 0.45)
        }))
        t += 1 / 90
    }
    frames.append(TouchFrame(timestamp: t, touches: []))
    return frames
}

@Suite struct PipelineTests {
    let swipeLeft = GestureEvent(.swipe(fingers: 4, direction: .left))

    @Test func recognisesASwipe() {
        let p = GesturePipeline()
        #expect(fourFingerSwipeLeft().flatMap { p.process(device: 1, frame: $0) } == [swipeLeft])
    }

    @Test func devicesDoNotDisturbEachOther() {
        let p = GesturePipeline()
        var events: [GestureEvent] = []
        for frame in fourFingerSwipeLeft() {
            events += p.process(device: 1, frame: frame)
            events += p.process(device: 2, frame: TouchFrame(timestamp: frame.timestamp, touches: []))
        }
        #expect(events == [swipeLeft])
    }

    @Test func lowerSensitivityNeedsMoreMovement() {
        let p = GesturePipeline()
        p.setSensitivity(0)
        let short = fourFingerSwipeLeft().map { f in
            TouchFrame(timestamp: f.timestamp, touches: f.touches.map { var t = $0; t.x = 0.5 + (t.x - 0.5) * 0.5; return t })
        }
        #expect(short.flatMap { p.process(device: 1, frame: $0) }.isEmpty)
    }
}

@Suite struct DispatcherTests {
    let left = Gesture.swipe(fingers: 4, direction: .left)
    let slide = Gesture.edgeSlide(edge: .right)

    @Test func discreteGestureRunsTheResolvedAction() {
        let bindings = [Binding(gesture: left, action: .previousWindow),
                        Binding(gesture: left, modifiers: .command, action: .previousDisplay)]
        #expect(Dispatcher.dispatch(GestureEvent(left), bindings: bindings, modifiers: .command, app: nil) == .run(.previousDisplay))
        #expect(Dispatcher.dispatch(GestureEvent(left), bindings: bindings, modifiers: [], app: nil) == .run(.previousWindow))
    }

    @Test func appBindingWins() {
        let bindings = [Binding(gesture: left, action: .previousWindow),
                        Binding(gesture: left, apps: ["com.apple.Safari"], action: .keyboardShortcut(KeyCombo(key: "[", modifiers: .command)))]
        #expect(Dispatcher.dispatch(GestureEvent(left), bindings: bindings, modifiers: [], app: "com.apple.Safari")
                == .run(.keyboardShortcut(KeyCombo(key: "[", modifiers: .command))))
    }

    @Test func continuousGestureAdjusts() {
        let bindings = [Binding(gesture: slide, action: .adjust(.volume))]
        #expect(Dispatcher.dispatch(GestureEvent(slide, delta: 0.1), bindings: bindings, modifiers: [], app: nil) == .adjust(.volume, 0.1))
    }

    @Test func mismatchedKindsDoNothing() {
        let bindings = [Binding(gesture: slide, action: .nextWindow), Binding(gesture: left, action: .adjust(.volume))]
        #expect(Dispatcher.dispatch(GestureEvent(slide, delta: 0.1), bindings: bindings, modifiers: [], app: nil) == nil)
        #expect(Dispatcher.dispatch(GestureEvent(left), bindings: bindings, modifiers: [], app: nil) == nil)
    }

    @Test func cgFlagsMapToModifiers() {
        #expect(Modifiers(CGEventFlags([.maskCommand, .maskAlternate, .maskAlphaShift])) == [.command, .option])
        #expect(Modifiers(CGEventFlags([.maskShift, .maskControl])) == [.shift, .control])
        #expect(Modifiers(CGEventFlags()) == [])
    }
}
