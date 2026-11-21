// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Model
@testable import Actions

/// Records every side effect as a string so tests assert on one ordered log.
final class Fake: WindowCommands, EventPosting, ProcessLaunching, WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    private var _errors: [ActionError] = []
    var launchResult: ActionError?

    var log: [String] { lock.withLock { _log } }
    var errors: [ActionError] { lock.withLock { _errors } }
    private func add(_ s: String) { lock.withLock { _log.append(s) } }
    func report(_ e: ActionError) { lock.withLock { _errors.append(e) } }

    func focusPreviousWindow() { add("prevWindow") }
    func focusNextWindow() { add("nextWindow") }
    func moveFocusedWindowToPreviousDisplay() { add("prevDisplay") }
    func moveFocusedWindowToNextDisplay() { add("nextDisplay") }
    func apply(layout: WindowLayout) { add("layout.\(layout.rawValue)") }
    func moveCursorToNextDisplay() { add("cursorNext") }

    func postKey(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool) {
        add("key.\(keyCode).\(flags.rawValue).\(down ? "down" : "up")")
    }
    func postMouse(_ button: MouseButton, down: Bool) { add("mouse.\(button.rawValue).\(down ? "down" : "up")") }
    func postMediaKey(_ key: Int32, down: Bool) { add("media.\(key).\(down ? "down" : "up")") }

    func launch(_ executable: String, arguments: [String], timeout: TimeInterval,
                completion: @escaping @Sendable (ActionError?) -> Void) {
        add("launch \(executable) \(arguments.joined(separator: "|")) \(Int(timeout))")
        completion(launchResult)
    }

    func openApp(bundleID: String) throws { add("app \(bundleID)") }
    func open(url: URL) throws { add("url \(url.absoluteString)") }
    func openFile(at url: URL) throws { add("file \(url.path)") }

    func runner(layout: @escaping @Sendable (Character) -> CGKeyCode? = { _ in nil }) -> ActionRunner {
        ActionRunner(windows: self, events: self, processes: self, workspace: self, keyCodeForCharacter: layout,
                     onError: { [self] in report($0) })
    }
}
