// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import Model

public struct SystemEventPoster: EventPosting {
    /// Stamped on every event we post (eventSourceUserData) so our own event tap can ignore them.
    public static let userData: Int64 = 0x4F47

    public init() {}

    private func post(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: Self.userData)
        event?.post(tap: .cghidEventTap)
    }

    public func postKey(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool) {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: down)
        event?.flags = flags
        post(event)
    }

    public func postMouse(_ button: MouseButton, down: Bool) {
        let at = CGEvent(source: nil)?.location ?? .zero
        let (type, cg): (CGEventType, CGMouseButton) = switch button {
        case .left: (down ? .leftMouseDown : .leftMouseUp, .left)
        case .right: (down ? .rightMouseDown : .rightMouseUp, .right)
        case .middle: (down ? .otherMouseDown : .otherMouseUp, .center)
        }
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                            mouseCursorPosition: at, mouseButton: cg)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        post(event)
    }

    public func postMediaKey(_ key: Int32, down: Bool) {
        let state: Int = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                       modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                       data1: (Int(key) << 16) | (state << 8), data2: -1)
        post(event?.cgEvent)
    }
}

/// Runs a child process off the calling thread; stderr (trimmed) becomes the error text.
public struct ProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(_ executable: String, arguments: [String], timeout: TimeInterval,
                       completion: @escaping @Sendable (ActionError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch {
                completion(.launchFailed(error.localizedDescription))
                return
            }
            let timedOut = Flag()
            let timer = DispatchWorkItem { timedOut.set(); process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            let output = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            if timedOut.value { completion(.timedOut) }
            else if process.terminationStatus != 0 {
                let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                completion(.scriptFailed(text.isEmpty ? "exit status \(process.terminationStatus)" : text))
            } else { completion(nil) }
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}

public struct SystemWorkspace: WorkspaceOpening {
    public init() {}

    // Launch errors that arrive asynchronously (app crashes on start) are not reported.
    public func openApp(bundleID: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActionError.appNotFound(bundleID)
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    public func open(url: URL) throws {
        guard NSWorkspace.shared.open(url) else { throw ActionError.failed("Could not open \(url.absoluteString)") }
    }

    public func openFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ActionError.failed("No such file: \(url.path)") }
        guard NSWorkspace.shared.open(url) else { throw ActionError.failed("Could not open \(url.path)") }
    }
}
