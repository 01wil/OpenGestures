// SPDX-License-Identifier: GPL-3.0-or-later

/// The window switcher's selection while the fingers stay down. Items are in most-recently-used order,
/// the current window first. The highlight starts where the plain jump would land (the previous window,
/// or the least recent one for "next"); every further stretch of `stepDistance` in either direction moves
/// it one window on, towards older windows for "previous" and newer ones for "next", wrapping.
public struct Switcher<Item> {
    /// Normalised trackpad units per step, about 1 cm on a laptop trackpad.
    public static var stepDistance: Double { 0.07 }

    public let items: [Item]
    public private(set) var selected: Int
    private let older: Bool
    /// Signed movement of the current stretch since its last step.
    private var travel = 0.0

    /// Nil with fewer than two items: there is nothing to switch to. `older` is true for "previous window".
    public init?(items: [Item], older: Bool) {
        guard items.count > 1 else { return nil }
        self.items = items
        self.older = older
        selected = older ? 1 : items.count - 1
    }

    public var selection: Item { items[selected] }

    /// Movement along the swipe axis. Returns whether the selection changed.
    public mutating func move(_ delta: Double) -> Bool {
        travel = travel * delta < 0 ? delta : travel + delta
        let steps = Int(abs(travel) / Self.stepDistance)
        guard steps != 0 else { return false }
        travel = travel.sign == .minus ? travel + Double(steps) * Self.stepDistance : travel - Double(steps) * Self.stepDistance
        selected = ((selected + (older ? steps : -steps)) % items.count + items.count) % items.count
        return true
    }
}
