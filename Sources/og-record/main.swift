// SPDX-License-Identifier: GPL-3.0-or-later
//
// Records trackpad frames to a JSON fixture for recogniser tests.
// Usage: og-record <output.json> [seconds]   (default 5 s, starts at the first touch)

import Foundation
import Model
import MultitouchBridge

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: og-record <output.json> [seconds]")
    exit(2)
}
let output = URL(fileURLWithPath: args[1])
let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5

final class Recorder: @unchecked Sendable {
    let lock = NSLock()
    var frames: [TouchFrame] = []
}
let recorder = Recorder()

MultitouchBridge.shared.start { frame in
    recorder.lock.withLock {
        // Skip the idle empty frames before the first touch.
        if recorder.frames.isEmpty && frame.touches.isEmpty { return }
        recorder.frames.append(frame)
    }
}
print("devices: \(MultitouchBridge.shared.deviceCount). Perform the gesture now…")

let deadline = Date().addingTimeInterval(120)
while true {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let (first, last) = recorder.lock.withLock { (recorder.frames.first?.timestamp, recorder.frames.last?.timestamp) }
    if let first, let last, last - first >= seconds { break }
    if Date() > deadline { print("no touches within 120 s"); exit(1) }
}
MultitouchBridge.shared.stop()

let frames = recorder.lock.withLock { recorder.frames }
let t0 = frames.first?.timestamp ?? 0
let normalised = frames.map { TouchFrame(timestamp: $0.timestamp - t0, touches: $0.touches) }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(normalised).write(to: output)
print("wrote \(frames.count) frames to \(output.path)")
