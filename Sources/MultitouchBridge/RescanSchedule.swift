// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Rescans for devices after wake or a hot-plug, retrying with backoff while none is found: the first
/// try after 1 s, then 2, 4, 8 and 16 s later, five in all. `begin` starts a new series and `cancel` ends
/// one; either way a try still queued from the old series does nothing.
@MainActor
public final class RescanSchedule {
    public static let delays: [TimeInterval] = [1, 2, 4, 8, 16]

    private let after: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let rescan: () -> Bool
    private var series = 0

    /// `rescan` returns true when it found a device (or there is nothing to retry); `after` runs its body
    /// on the main actor after the delay.
    public init(after: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void, rescan: @escaping () -> Bool) {
        self.after = after
        self.rescan = rescan
    }

    public func begin() {
        series += 1
        schedule(try: 0, series: series)
    }

    public func cancel() { series += 1 }

    private func schedule(try n: Int, series: Int) {
        after(Self.delays[n]) { [weak self] in
            guard let self, series == self.series else { return }
            if !rescan(), n + 1 < Self.delays.count { schedule(try: n + 1, series: series) }
        }
    }
}
