// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Model

public enum ActionError: Error, Equatable, Sendable {
    case unknownKey(String)
    case invalidURL(String)
    case appNotFound(String)
    case scriptFailed(String)
    case timedOut
    case launchFailed(String)
    case notDiscrete
    case failed(String)
}

/// Wired by the app to the Windows module.
public protocol WindowCommands: Sendable {
    func focusPreviousWindow() throws
    func focusNextWindow() throws
    func moveFocusedWindowToPreviousDisplay() throws
    func moveFocusedWindowToNextDisplay() throws
    func apply(layout: WindowLayout) throws
    func moveCursorToNextDisplay() throws
}

public protocol EventPosting: Sendable {
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool)
    /// At the current cursor location.
    func postMouse(_ button: MouseButton, down: Bool)
    /// `key` is an NX_KEYTYPE_* code.
    func postMediaKey(_ key: Int32, down: Bool)
}

public protocol ProcessLaunching: Sendable {
    /// Returns immediately; `completion` runs later on any thread with nil on success.
    func launch(_ executable: String, arguments: [String], timeout: TimeInterval,
                completion: @escaping @Sendable (ActionError?) -> Void)
}

public protocol WorkspaceOpening: Sendable {
    func openApp(bundleID: String) throws
    func open(url: URL) throws
    func openFile(at url: URL) throws
}
