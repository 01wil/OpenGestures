// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// Remembers, per window, the frame it had before one of our layouts so a repeat of the layout (or a
/// drag away) can put it back. Pure; all rects share one coordinate space (AX, top-left origin).
public struct RestoreMemory<Key: Hashable> {
    public enum Outcome: Equatable { case apply, restore(CGRect) }

    static var tolerance: CGFloat { 4 }
    /// Windows remembered at once; a new one past this evicts the one saved longest ago.
    public static var capacity: Int { 50 }

    private struct Entry { var original: CGRect; var requested: CGRect; var placed: CGRect; var serial: Int }
    private var entries: [Key: Entry] = [:]
    private var nextSerial = 0

    public init() {}

    public func original(of key: Key) -> CGRect? { entries[key]?.original }

    /// Already at `target` (or, for the same request, at the frame the system actually gave, e.g. a snapped
    /// Terminal grid) with a saved frame: restore it and forget. Otherwise remember the frame the
    /// window had before our first layout and apply. A window already at `target` with nothing saved
    /// has nothing worth restoring, so nothing is saved.
    public mutating func toggle(_ key: Key, current: CGRect, target: CGRect) -> Outcome {
        if let e = entries[key],
           Self.near(current, target) || (Self.near(current, e.placed) && Self.near(target, e.requested)) {
            entries[key] = nil
            return .restore(e.original)
        }
        if entries[key] != nil {
            entries[key]?.requested = target
        } else if !Self.near(current, target) {
            if entries.count >= Self.capacity, let oldest = entries.min(by: { $0.value.serial < $1.value.serial })?.key {
                entries[oldest] = nil
            }
            entries[key] = Entry(original: current, requested: target, placed: target, serial: nextSerial)
            nextSerial += 1
        }
        return .apply
    }

    /// The frame the window really took after our setFrame (the system may clamp the size).
    public mutating func placed(_ key: Key, at frame: CGRect) { entries[key]?.placed = frame }

    /// A size notification: forgets and returns true when the size is not the one we placed.
    @discardableResult
    public mutating func userResized(_ key: Key, to size: CGSize) -> Bool {
        guard let e = entries[key],
              abs(size.width - e.placed.width) > Self.tolerance || abs(size.height - e.placed.height) > Self.tolerance
        else { return false }
        entries[key] = nil
        return true
    }

    public mutating func forget(_ key: Key) { entries[key] = nil }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
