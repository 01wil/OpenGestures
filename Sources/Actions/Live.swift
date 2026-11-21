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
        if let event { event.flags = Self.keyFlags(keyCode: keyCode, flags: flags, existing: event.flags) }
        post(event)
    }

    /// The combo's modifiers merged with the bits macOS sets on the key itself (secondaryFn, numericPad),
    /// plus the ones a real keyboard produces for arrows, F-keys and the navigation cluster.
    static func keyFlags(keyCode: CGKeyCode, flags: CGEventFlags, existing: CGEventFlags) -> CGEventFlags {
        var result = flags.union(existing.intersection([.maskSecondaryFn, .maskNumericPad]))
        switch keyCode {
        case 123...126: result.formUnion([.maskSecondaryFn, .maskNumericPad])
        case 115, 116, 117, 119, 121, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90:
            result.insert(.maskSecondaryFn)
        default: break
        }
        return result
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

/// Runs a child process without blocking a thread: it is spawned in its own process group, its exit is
/// watched through a dispatch source, and stderr (capped, trimmed) becomes the error text. Background
/// jobs the script leaves behind neither delay nor fail it; on timeout the whole group gets SIGTERM, then
/// SIGKILL two seconds later.
public struct ProcessLauncher: ProcessLaunching {
    static let stderrCap = 64 * 1024
    static let killGrace: TimeInterval = 2

    public init() {}

    public func launch(_ executable: String, arguments: [String], timeout: TimeInterval,
                       completion: @escaping @Sendable (ActionError?) -> Void) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return completion(.launchFailed(String(cString: strerror(errno)))) }
        var actions: posix_spawn_file_actions_t?
        var attr: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attr)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        // Only 0, 1 and 2 reach the child; every other descriptor of ours is closed at exec.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attr, argv, environ)
        close(fds[1])
        guard rc == 0 else {
            close(fds[0])
            return completion(.launchFailed(String(cString: strerror(rc))))
        }
        Job(pid: pid, readFD: fds[0], completion: completion).start(timeout: timeout)
    }

    /// All state is touched on `queue` only.
    private final class Job: @unchecked Sendable {
        let pid: pid_t
        let readFD: Int32
        let completion: @Sendable (ActionError?) -> Void
        let queue = DispatchQueue(label: "opengestures.process")
        var output = Data()
        var exited = false
        var reported = false
        var reader: DispatchSourceRead?
        var exitSource: DispatchSourceProcess?

        init(pid: pid_t, readFD: Int32, completion: @escaping @Sendable (ActionError?) -> Void) {
            self.pid = pid; self.readFD = readFD; self.completion = completion
        }

        func start(timeout: TimeInterval) {
            _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)
            let reader = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
            reader.setEventHandler { [self] in if !drain() { reader.cancel() } }
            reader.setCancelHandler { [readFD] in close(readFD) }
            self.reader = reader
            let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            exit.setEventHandler { [self] in finish() }
            exitSource = exit
            reader.resume()
            exit.resume()
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                guard !exited else { return }
                report(.timedOut)
                killpg(pid, SIGTERM)
                queue.asyncAfter(deadline: .now() + ProcessLauncher.killGrace) { [self] in
                    if !exited { killpg(pid, SIGKILL) }
                }
            }
        }

        /// Reads what is available (past the cap it is discarded); false at EOF or on error.
        private func drain() -> Bool {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(readFD, &buffer, buffer.count)
                if n > 0 {
                    if output.count < ProcessLauncher.stderrCap {
                        output.append(contentsOf: buffer[0..<min(n, ProcessLauncher.stderrCap - output.count)])
                    }
                } else { return n < 0 && errno == EAGAIN }
            }
        }

        private func finish() {
            exited = true
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            _ = drain()
            reader?.cancel()
            exitSource?.cancel()
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            if code == 0 { return report(nil) }
            let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            report(.scriptFailed(text.isEmpty ? "exit status \(code)" : text))
        }

        private func report(_ error: ActionError?) {
            guard !reported else { return }
            reported = true
            completion(error)
        }
    }
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
