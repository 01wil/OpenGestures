// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import AppKit
import ApplicationServices

/// Keeps `WindowHistory` current from three signals: app activation, per-window focus changes inside
/// the front app (AXObserver, since macOS posts nothing for those), and a WindowServer z-order seed.
@MainActor
public final class WindowTracker {
    private var history = WindowHistory<CGWindowID>()
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var activationToken: NSObjectProtocol?

    public init() {}

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func start() {
        guard activationToken == nil else { return }
        history.seed(WindowList.items(onScreenOnly: true).map(\.id))
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.appActivated(pid) } }
        }
        if let front = NSWorkspace.shared.frontmostApplication { appActivated(front.processIdentifier) }
    }

    public func stop() {
        if let t = activationToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        activationToken = nil
        observe(pid: 0)
    }

    /// The window to focus for a previous / next request, or nil. Closed windows are pruned first.
    func previous() -> (id: CGWindowID, pid: pid_t)? { step { $0.previous(now: $1) } }
    func next() -> (id: CGWindowID, pid: pid_t)? { step { $0.next(now: $1) } }

    /// Every known window that still exists, most recently used first.
    func ordered() -> [WindowList.Item] {
        let alive = Dictionary(WindowList.items(onScreenOnly: false).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        history.retain(alive: Set(alive.keys))
        history.settle()
        return history.order.compactMap { alive[$0] }
    }

    /// The most recently used window that still exists, if any.
    func current() -> (id: CGWindowID, pid: pid_t)? { step { h, _ in h.order.first } }

    private func step(_ f: (inout WindowHistory<CGWindowID>, TimeInterval) -> CGWindowID?) -> (id: CGWindowID, pid: pid_t)? {
        let alive = Dictionary(WindowList.items(onScreenOnly: false).map { ($0.id, $0.pid) }, uniquingKeysWith: { a, _ in a })
        history.retain(alive: Set(alive.keys))
        guard let id = f(&history, now), let pid = alive[id] else { return nil }
        return (id, pid)
    }

    private func appActivated(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        observe(pid: pid)
        focusChanged(pid: pid)
    }

    fileprivate func focusChanged(pid: pid_t) {
        guard let w = AX.focusedWindow(pid: pid), let id = AX.windowID(w) else { return }
        history.activated(id, now: now)
    }

    private func observe(pid: pid_t) {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = nil
        }
        observedPID = pid
        guard pid != 0, AX.trusted else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.focusChanged(pid: tracker.observedPID) }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let app = AX.application(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(obs, app, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }
}
