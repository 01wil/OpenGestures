// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Model

@Suite struct GestureIDTests {
    @Test(arguments: [
        ("swipe.4.left", Gesture.swipe(fingers: 4, direction: .left)),
        ("swipe.3.up", .swipe(fingers: 3, direction: .up)),
        ("tap.2", .tap(fingers: 2)),
        ("pinch.4.in", .pinch(fingers: 4, direction: .pinchIn)),
        ("pinch.2.out", .pinch(fingers: 2, direction: .pinchOut)),
        ("rotate.cw", .rotate(.clockwise)),
        ("rotate.ccw", .rotate(.counterClockwise)),
        ("tiptap.left", .tipTap(side: .left)),
        ("edgeswipe.right", .edgeSwipe(edge: .right)),
        ("cornertap.topleft", .cornerTap(corner: .topLeft)),
        ("edgeslide.left", .edgeSlide(edge: .left)),
        ("forceclick.3", .forceClick(fingers: 3)),
    ])
    func roundTrips(id: String, gesture: Gesture) {
        #expect(Gesture(id: id) == gesture)
        #expect(gesture.id == id)
    }

    @Test(arguments: ["", "swipe", "swipe.4", "swipe.9.left", "swipe.1.left", "tap.0", "tap.6",
                      "pinch.1.in", "rotate.left", "tiptap.up", "edgeswipe.middle", "forceclick.0", "forceclick.6", "nonsense.1"])
    func rejectsInvalid(id: String) {
        #expect(Gesture(id: id) == nil)
    }

    @Test func onlyEdgeSlideIsContinuous() {
        #expect(Gesture.edgeSlide(edge: .left).isContinuous)
        #expect(!Gesture.swipe(fingers: 4, direction: .left).isContinuous)
    }
}

@Suite struct CodableTests {
    @Test func bindingEncodesGestureAsString() throws {
        let binding = Binding(
            gesture: .swipe(fingers: 4, direction: .left),
            modifiers: [.command],
            action: .previousDisplay
        )
        let json = String(decoding: try JSONEncoder().encode(binding), as: UTF8.self)
        #expect(json.contains("\"gesture\":\"swipe.4.left\""))
        #expect(json.contains("\"modifiers\":[\"cmd\"]"))
        let back = try JSONDecoder().decode(Binding.self, from: Data(json.utf8))
        #expect(back == binding)
    }

    @Test(arguments: [
        Action.keyboardShortcut(KeyCombo(key: "t", modifiers: [.command, .shift])),
        .openApp(bundleID: "com.apple.Safari"),
        .openURL("https://example.com"),
        .openFile(path: "~/Documents"),
        .shellScript("say hi"),
        .appleScript("beep"),
        .shortcut(name: "My Shortcut"),
        .systemKey(.playPause),
        .mouseClick(.middle),
        .previousWindow, .nextWindow,
        .previousDisplay, .nextDisplay, .cursorToNextDisplay,
        .windowLayout(.leftHalf),
        .adjust(.volume),
    ])
    func actionRoundTrips(action: Action) throws {
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }

    @Test func actionJSONIsFlat() throws {
        let json = String(decoding: try JSONEncoder().encode(Action.openApp(bundleID: "com.apple.Safari")), as: UTF8.self)
        #expect(json.contains("\"type\":\"openApp\""))
        #expect(json.contains("\"bundleID\":\"com.apple.Safari\""))
    }

    @Test func windowActionIgnoresLegacyPreviewKey() throws {
        let old = try JSONDecoder().decode(Action.self, from: Data(#"{"type":"previousWindow","preview":true}"#.utf8))
        #expect(old == .previousWindow)
        #expect(String(decoding: try JSONEncoder().encode(Action.nextWindow), as: UTF8.self) == #"{"type":"nextWindow"}"#)
    }

    @Test func unknownActionTypeFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Action.self, from: Data(#"{"type":"launchRockets"}"#.utf8))
        }
    }

    @Test func modifiersEncodeInStableOrder() throws {
        let json = String(decoding: try JSONEncoder().encode(Modifiers([.shift, .command, .control, .option])), as: UTF8.self)
        #expect(json == #"["cmd","shift","ctrl","opt"]"#)
    }
}
