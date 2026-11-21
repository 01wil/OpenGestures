// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import ApplicationServices

/// One AXObserver per window we hold a saved frame for, reporting move, resize and close. A per-window
/// refcon carries the id because a destroyed element can no longer be mapped to its CGWindowID.
@MainActor
final class RestoreWatcher {
    enum Event { case moved, resized, closed }

    private final class Box { let id: CGWindowID; unowned let owner: RestoreWatcher
        init(_ id: CGWindowID, _ owner: RestoreWatcher) { self.id = id; self.owner = owner } }
    private struct Entry { let observer: AXObserver; let element: AXUIElement; let pid: pid_t; let box: Unmanaged<Box> }

    var onEvent: ((CGWindowID, Event) -> Void)?
    private var entries: [CGWindowID: Entry] = [:]

    func element(for id: CGWindowID) -> AXUIElement? { entries[id]?.element }

    /// Watched windows, all or only those owned by `pid`.
    func ids(pid: pid_t? = nil) -> [CGWindowID] {
        entries.filter { pid == nil || $0.value.pid == pid }.map(\.key)
    }

    func watch(_ id: CGWindowID, _ window: AXUIElement) {
        var pid: pid_t = 0
        guard entries[id] == nil, AXUIElementGetPid(window, &pid) == .success else { return }
        let callback: AXObserverCallback = { _, _, note, refcon in
            guard let refcon else { return }
            let box = Unmanaged<Box>.fromOpaque(refcon).takeUnretainedValue()
            let event: Event = note as String == kAXMovedNotification ? .moved
                : note as String == kAXResizedNotification ? .resized : .closed
            MainActor.assumeIsolated { box.owner.onEvent?(box.id, event) }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let box = Unmanaged.passRetained(Box(id, self))
        for n in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(obs, window, n as CFString, box.toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        entries[id] = Entry(observer: obs, element: window, pid: pid, box: box)
    }

    func unwatch(_ id: CGWindowID) {
        guard let e = entries.removeValue(forKey: id) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(e.observer), .defaultMode)
        e.box.release()
    }
}
