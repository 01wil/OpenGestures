// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Most-recently-used list of window ids, walked by previous / next gestures.
///
/// `order[0]` is the current window. The first `previous` targets `order[1]` (back to where you came
/// from); the first `next` targets the least recent window. That starts a walk over a frozen snapshot:
/// further `previous` calls go one step older, `next` one step newer, both wrapping, however slowly
/// they come. The walk ends only when the user activates a window themselves (or `settle()`); the
/// window they walked to is then recorded as used, followed by the one they picked.
///
/// Activations that arrive within `echoWindow` seconds of a step are our own focus change echoing back
/// (apps often report another of their windows first) and are ignored. Windows that close mid-walk
/// drop out of the snapshot without ending the walk.
public struct WindowHistory<ID: Hashable> {
    public static var defaultEchoWindow: TimeInterval { 0.5 }

    public private(set) var order: [ID] = []
    private let limit: Int
    private let echoWindow: TimeInterval
    private var walk: (snapshot: [ID], cursor: Int, last: TimeInterval)?

    public init(limit: Int = 50, echoWindow: TimeInterval = defaultEchoWindow) {
        self.limit = limit
        self.echoWindow = echoWindow
    }

    public mutating func activated(_ id: ID, now: TimeInterval) {
        if let w = walk {
            if w.snapshot[w.cursor] == id || now - w.last < echoWindow { return }
            settle()
        }
        promote(id)
    }

    /// Adds unknown ids at the back, in the given (front-to-back) order. Never reorders known ones.
    public mutating func seed(_ ids: [ID]) {
        for id in ids where !order.contains(id) && order.count < limit { order.append(id) }
    }

    /// Drops windows that no longer exist, from the history and from a walk in progress.
    public mutating func retain(alive: Set<ID>) {
        order.removeAll { !alive.contains($0) }
        guard var w = walk else { return }
        let target = w.snapshot[w.cursor]
        // Dead windows before the cursor shift it; a dead target leaves the cursor on the next older one.
        w.cursor -= w.snapshot[..<w.cursor].filter { !alive.contains($0) }.count
        w.snapshot.removeAll { !alive.contains($0) }
        if !alive.contains(target) { w.cursor -= 1 }
        walk = w.snapshot.count > 1 ? (w.snapshot, (w.cursor + w.snapshot.count) % w.snapshot.count, w.last) : nil
    }

    /// Ends a walk in progress, recording the walked-to window as the most recent.
    public mutating func settle() {
        guard let w = walk else { return }
        walk = nil
        promote(w.snapshot[w.cursor])
    }

    public mutating func previous(now: TimeInterval) -> ID? { step(now, by: 1) }
    public mutating func next(now: TimeInterval) -> ID? { step(now, by: -1) }

    private mutating func step(_ now: TimeInterval, by delta: Int) -> ID? {
        let w = walk ?? (order, 0, now)
        guard w.snapshot.count > 1 else { return nil }
        let cursor = (w.cursor + delta + w.snapshot.count) % w.snapshot.count
        walk = (w.snapshot, cursor, now)
        return w.snapshot[cursor]
    }

    private mutating func promote(_ id: ID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > limit { order.removeLast() }
    }
}
