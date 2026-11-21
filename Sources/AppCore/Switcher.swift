// SPDX-License-Identifier: GPL-3.0-or-later

import Model

/// The window switcher's selection while the fingers stay down. Items are in most-recently-used order,
/// the current window first. The highlight starts where the plain jump would land (the previous window,
/// or the least recent one for "next") and each further `stepDistance` of movement moves it one window,
/// wrapping. The strip is laid out so that the highlight moves the way the fingers do.
public struct Switcher<Item> {
    /// Normalised trackpad units per step, about 1 cm on a laptop trackpad.
    public static var stepDistance: Double { 0.07 }

    public let items: [Item]
    public private(set) var selected: Int
    /// Older windows lie to the left of the current one; otherwise to the right.
    public let olderToTheLeft: Bool
    /// Movement towards older windows since the last step.
    private var travel = 0.0

    /// Nil with fewer than two items: there is nothing to switch to. `older` is true for "previous window";
    /// `swipe` is the swipe that opened the switcher.
    public init?(items: [Item], older: Bool, swipe: Gesture.Direction) {
        guard items.count > 1 else { return nil }
        self.items = items
        selected = older ? 1 : items.count - 1
        // "Previous" reached older windows by moving in the swipe's direction, "next" by moving against it.
        olderToTheLeft = older != (swipe == .right || swipe == .up)
    }

    public var selection: Item { items[selected] }

    /// Signed movement along the swipe axis (positive = right/up). Returns whether the selection changed.
    public mutating func move(_ delta: Double) -> Bool {
        travel += olderToTheLeft ? -delta : delta
        let steps = Int(travel / Self.stepDistance)
        guard steps != 0 else { return false }
        travel -= Double(steps) * Self.stepDistance
        selected = ((selected + steps) % items.count + items.count) % items.count
        return true
    }
}
