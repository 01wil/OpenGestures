// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Most-recently-used list of window ids with Vorssaint-style quick-flick navigation.
///
/// Semantics: `order[0]` is the current window. A fresh `previous` targets `order[1]` (so one flick
/// toggles back); a fresh `next` targets the least recent entry. Calls less than `sessionTimeout`
/// seconds apart form a session that walks a frozen snapshot: `previous` goes one step older,
/// `next` one step newer, both wrapping. During a session `order` is not touched: the activation
/// echo of our own focus change (`activated(target)`) is ignored. When the session times out, or a
/// different window is activated, the session is committed by rotating the snapshot so its target is
/// first. Rotation keeps the ring's order, so repeated slow `previous` calls visit every window (the
/// window left behind goes to the back) instead of toggling between two, and `next` undoes `previous`.
public struct WindowHistory<ID: Hashable> {
    public static var defaultSessionTimeout: TimeInterval { 1.0 }

    public private(set) var order: [ID] = []
    private let limit: Int
    private let sessionTimeout: TimeInterval
    private var session: (snapshot: [ID], cursor: Int, last: TimeInterval)?

    public init(limit: Int = 50, sessionTimeout: TimeInterval = defaultSessionTimeout) {
        self.limit = limit
        self.sessionTimeout = sessionTimeout
    }

    public mutating func activated(_ id: ID, now: TimeInterval) {
        expire(now)
        if let s = session, s.snapshot[s.cursor] == id { return }
        session = nil
        promote(id)
    }

    /// Adds unknown ids at the back, in the given (front-to-back) order. Never reorders known ones.
    public mutating func seed(_ ids: [ID]) {
        for id in ids where !order.contains(id) && order.count < limit { order.append(id) }
    }

    /// Drops windows that no longer exist.
    public mutating func retain(alive: Set<ID>) {
        let before = order.count
        order.removeAll { !alive.contains($0) }
        if order.count != before { session = nil }
    }

    public mutating func previous(now: TimeInterval) -> ID? { step(now, by: 1) }
    public mutating func next(now: TimeInterval) -> ID? { step(now, by: -1) }

    private mutating func step(_ now: TimeInterval, by delta: Int) -> ID? {
        expire(now)
        guard order.count > 1 else { return nil }
        let snapshot = session?.snapshot ?? order
        let cursor = ((session?.cursor ?? 0) + delta + snapshot.count) % snapshot.count
        session = (snapshot, cursor, now)
        return snapshot[cursor]
    }

    private mutating func expire(_ now: TimeInterval) {
        guard let s = session, now - s.last >= sessionTimeout else { return }
        commit(s)
    }

    private mutating func commit(_ s: (snapshot: [ID], cursor: Int, last: TimeInterval)) {
        session = nil
        // Keep only windows still in `order` (some may have closed during the session).
        let rotated = Array(s.snapshot[s.cursor...] + s.snapshot[..<s.cursor]).filter(order.contains)
        order = rotated + order.filter { !rotated.contains($0) }
    }

    private mutating func promote(_ id: ID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > limit { order.removeLast() }
    }
}
