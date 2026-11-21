// SPDX-License-Identifier: GPL-3.0-or-later
//
// Records trackpad gestures as JSON fixtures for the recogniser tests.
//
//   og-record <output.json>          record one gesture
//   og-record --guided <directory>   walk through a list of gestures, one file each
//
// A recording starts at the first touch and ends when every finger has been lifted for 0.3 s.
// Only the first trackpad that is touched is recorded. Pause OpenGestures while recording.

import Foundation
import Model
import MultitouchBridge

setvbuf(stdout, nil, _IONBF, 0)

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var device: Int?
    private var frames: [TouchFrame] = []
    private var liftedAt: Date?

    func feed(_ device: Int, _ frame: TouchFrame) {
        lock.withLock {
            if self.device == nil {
                guard !frame.touches.isEmpty else { return }
                self.device = device
            }
            guard self.device == device else { return }
            frames.append(frame)
            let anyTouching = frame.touches.contains { $0.isTouching }
            liftedAt = anyTouching ? nil : (liftedAt ?? Date())
        }
    }

    /// The recorded frames once all fingers have been up for `quiet` seconds, else nil.
    func finished(quiet: Double = 0.3) -> [TouchFrame]? {
        lock.withLock {
            // Wall clock: the trackpad may stop sending frames once every finger is up.
            guard let lifted = liftedAt, Date().timeIntervalSince(lifted) >= quiet else { return nil }
            return frames
        }
    }

    func reset() { lock.withLock { device = nil; frames = []; liftedAt = nil } }
}

let recorder = Recorder()

/// Waits for one complete gesture.
func recordOne(timeout: Double = 120) -> [TouchFrame]? {
    recorder.reset()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if let frames = recorder.finished() { return frames }
    }
    return nil
}

func write(_ frames: [TouchFrame], to url: URL) throws {
    let t0 = frames.first?.timestamp ?? 0
    let shifted = frames.map { TouchFrame(timestamp: $0.timestamp - t0, touches: $0.touches) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(shifted).write(to: url)
}

/// Gesture id (or "none" for things that must not fire) and the instruction shown.
let guide: [(id: String, hint: String)] = [
    ("tap.1", "tap once with 1 finger"),
    ("tap.2", "tap once with 2 fingers"),
    ("tap.3", "tap once with 3 fingers"),
    ("tap.4", "tap once with 4 fingers"),
    ("tap.5", "tap once with all 5 fingers"),
    ("swipe.3.left", "swipe left with 3 fingers"),
    ("swipe.4.left", "swipe left with 4 fingers"),
    ("swipe.4.right", "swipe right with 4 fingers"),
    ("swipe.4.up", "swipe up with 4 fingers"),
    ("swipe.4.down", "swipe down with 4 fingers"),
    ("swipe.5.left", "swipe left with 5 fingers"),
    ("swipe.5.up", "swipe up with 5 fingers"),
    ("pinch.4.in", "pinch in with 4 fingers (thumb + 3)"),
    ("pinch.4.out", "spread out with 4 fingers (thumb + 3)"),
    ("pinch.5.in", "pinch in with all 5 fingers"),
    ("rotate.cw", "rotate clockwise with 2 fingers"),
    ("rotate.ccw", "rotate counter-clockwise with 2 fingers"),
    ("tiptap.left", "rest one finger, then tap once to its LEFT with another"),
    ("tiptap.right", "rest one finger, then tap once to its RIGHT with another"),
    ("edgeswipe.left", "start at the very LEFT edge and swipe inward with 1 finger"),
    ("edgeswipe.right", "start at the very RIGHT edge and swipe inward with 1 finger"),
    ("cornertap.topleft", "tap once in the TOP-LEFT corner with 1 finger"),
    ("edgeslide.right", "put 1 finger on the RIGHT edge and slide it up along the edge"),
    ("none", "rest your thumb or palm on the trackpad for 2 seconds, then lift"),
    ("none", "move the pointer around slowly with 1 finger for 2 seconds"),
]

let args = CommandLine.arguments
MultitouchBridge.shared.start(perDevice: { recorder.feed($0, $1) })
print("trackpads found: \(MultitouchBridge.shared.deviceCount)")

if args.count == 3, args[1] == "--guided" {
    let dir = URL(fileURLWithPath: args[2], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = Int(Date().timeIntervalSince1970)
    for (i, step) in guide.enumerated() {
        print("\n[\(i + 1)/\(guide.count)] Please \(step.hint), then lift all fingers.")
        guard let frames = recordOne() else { print("No touch within 120 s, stopping."); exit(1) }
        let url = dir.appendingPathComponent("\(step.id)__real-\(stamp)-\(i + 1).json")
        try write(frames, to: url)
        print("  saved \(url.lastPathComponent) (\(frames.count) frames)")
        Thread.sleep(forTimeInterval: 0.5)
    }
    print("\nDone, thank you!")
} else if args.count == 2 {
    print("Perform the gesture now…")
    guard let frames = recordOne() else { print("No touch within 120 s."); exit(1) }
    try write(frames, to: URL(fileURLWithPath: args[1]))
    print("wrote \(frames.count) frames to \(args[1])")
} else {
    print("usage: og-record <output.json> | og-record --guided <directory>")
    exit(2)
}
MultitouchBridge.shared.stop()
