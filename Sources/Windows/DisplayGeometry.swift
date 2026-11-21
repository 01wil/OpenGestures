// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import CoreGraphics
import Model

/// Pure display and frame math. All rects are AppKit (bottom-left origin) unless a name says AX.
public enum DisplayGeometry {
    static let tolerance: CGFloat = 8

    /// Indices of `frames` ordered left to right, then bottom to top (minY), as Vorssaint does.
    public static func ordered(_ frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            let l = frames[a], r = frames[b]
            if l.minX != r.minX { return l.minX < r.minX }
            if l.minY != r.minY { return l.minY < r.minY }
            return a < b
        }
    }

    /// Next/previous display index with wrap-around; nil with fewer than two displays.
    public static func adjacent(to index: Int, in frames: [CGRect], forward: Bool) -> Int? {
        guard frames.count > 1, frames.indices.contains(index) else { return nil }
        let order = ordered(frames)
        guard let pos = order.firstIndex(of: index) else { return nil }
        return order[(pos + (forward ? 1 : order.count - 1)) % order.count]
    }

    /// Keep size (shrunk to fit) and edge insets; a window filling the source fills the target.
    public static func rect(moving current: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return current }
        if current.width >= source.width - tolerance, current.height >= source.height - tolerance {
            return target
        }
        let w = min(target.width, max(1, current.width))
        let h = min(target.height, max(1, current.height))
        // Horizontal prefers the left edge, vertical the top (AppKit maxY): a window flush with the
        // opposite edge stays flush with it.
        let x = origin(current.minX, current.maxX, source.minX, source.maxX, target.minX, target.maxX, w, preferMax: false)
        let y = origin(current.minY, current.maxY, source.minY, source.maxY, target.minY, target.maxY, h, preferMax: true)
        return CGRect(x: min(max(x, target.minX), target.maxX - w),
                      y: min(max(y, target.minY), target.maxY - h),
                      width: w, height: h).integral
    }

    private static func origin(_ cMin: CGFloat, _ cMax: CGFloat, _ sMin: CGFloat, _ sMax: CGFloat,
                               _ tMin: CGFloat, _ tMax: CGFloat, _ size: CGFloat, preferMax: Bool) -> CGFloat {
        let minInset = cMin - sMin, maxInset = sMax - cMax
        // With almost no slack, flush-edge detection is a coin flip; keep the preferred edge.
        if (sMax - sMin) - (cMax - cMin) <= tolerance {
            return preferMax ? tMax - maxInset - size : tMin + minInset
        }
        if preferMax {
            return minInset <= tolerance && minInset < maxInset ? tMin + minInset : tMax - maxInset - size
        }
        return maxInset <= tolerance && maxInset < minInset ? tMax - maxInset - size : tMin + minInset
    }

    /// `primaryMaxY` is the height of the primary display (AppKit frame.maxY of the screen at 0,0).
    public static func appKit(fromAX r: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryMaxY - r.minY - r.height, width: r.width, height: r.height)
    }

    public static func ax(fromAppKit r: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryMaxY - r.maxY, width: r.width, height: r.height)
    }

    /// Target frame for a layout inside `visible`. Halves use floor so they tile without overlap;
    /// the right/top part takes the remainder.
    public static func frame(for layout: WindowLayout, windowSize: CGSize, in v: CGRect) -> CGRect {
        let w1 = (v.width / 2).rounded(.down), h1 = (v.height / 2).rounded(.down)
        let left = CGRect(x: v.minX, y: v.minY, width: w1, height: v.height)
        let right = CGRect(x: v.minX + w1, y: v.minY, width: v.width - w1, height: v.height)
        let bottom = CGRect(x: v.minX, y: v.minY, width: v.width, height: h1)
        let top = CGRect(x: v.minX, y: v.minY + h1, width: v.width, height: v.height - h1)
        switch layout {
        case .maximize: return v
        case .leftHalf: return left
        case .rightHalf: return right
        case .bottomHalf: return bottom
        case .topHalf: return top
        case .topLeft: return left.intersection(top)
        case .topRight: return right.intersection(top)
        case .bottomLeft: return left.intersection(bottom)
        case .bottomRight: return right.intersection(bottom)
        case .center:
            let w = min(v.width, windowSize.width), h = min(v.height, windowSize.height)
            return CGRect(x: v.minX + ((v.width - w) / 2).rounded(.down),
                          y: v.minY + ((v.height - h) / 2).rounded(.down), width: w, height: h)
        }
    }

    /// Frame for a window the user just pulled out of a layout (AX space, y down): the restored size
    /// with the pointer at the same relative x on the title bar and the same depth below its top,
    /// kept inside `visible` and never above its top edge.
    public static func restoredFrame(dragging current: CGRect, restoreSize: CGSize, pointer: CGPoint, in visible: CGRect) -> CGRect {
        let ratio = current.width > 0 ? min(max((pointer.x - current.minX) / current.width, 0), 1) : 0.5
        let depth = min(max(pointer.y - current.minY, 0), restoreSize.height)
        let x = restoreSize.width <= visible.width
            ? min(max(pointer.x - ratio * restoreSize.width, visible.minX), visible.maxX - restoreSize.width)
            : visible.minX
        return CGRect(origin: CGPoint(x: x, y: max(pointer.y - depth, visible.minY)), size: restoreSize)
    }
}
