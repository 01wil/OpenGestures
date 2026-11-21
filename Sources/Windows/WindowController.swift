// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import AppKit
import Model

public struct WindowInfo: Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    /// Empty when neither Accessibility nor the window server will tell.
    public let title: String

    public init(id: CGWindowID, pid: pid_t, title: String) {
        self.id = id
        self.pid = pid
        self.title = title
    }
}

/// The window operations the Actions module calls. All return false when they could not act (no
/// Accessibility permission, no target, single display); none throws, blocks long, or moves anything
/// outside the intended window / cursor. Call `start()` once; main actor only.
@MainActor
public final class WindowController {
    private let tracker = WindowTracker()

    public init() {}

    public func start() { tracker.start() }

    /// Re-attaches focus tracking, e.g. once Accessibility has been granted.
    public func restart() {
        tracker.stop()
        tracker.start()
    }

    // MARK: Focus

    @discardableResult public func focusPreviousWindow() -> Bool { focus(tracker.previous()) }
    @discardableResult public func focusNextWindow() -> Bool { focus(tracker.next()) }
    @discardableResult public func focus(_ window: WindowInfo) -> Bool { focus((window.id, window.pid)) }

    /// Known windows, most recently used first (the current one first), for the switcher.
    public func windows() -> [WindowInfo] {
        let items = tracker.ordered()
        var titles: [CGWindowID: String] = [:]
        for pid in Set(items.map(\.pid)) {
            for w in AX.value(AX.application(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if let id = AX.windowID(w), let title = AX.value(w, kAXTitleAttribute) as? String { titles[id] = title }
            }
        }
        return items.map { WindowInfo(id: $0.id, pid: $0.pid, title: titles[$0.id] ?? $0.title ?? "") }
    }

    private func focus(_ target: (id: CGWindowID, pid: pid_t)?) -> Bool {
        guard AX.trusted, let (id, pid) = target, let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden { app.unhide() }
        var fronted = false
        if let w = AX.window(id: id, pid: pid) {
            raise(w, pid: pid)
        } else {
            // Not listed by AX: another Space. Public API cannot front it, so use the window-server path.
            fronted = PrivateFront.front(windowID: id, pid: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let w = AX.window(id: id, pid: pid) { Self.raise(w, pid: pid) }
            }
        }
        // A never-active menu bar app cannot hand activation over, so ask the target to come forward too.
        if AX.set(AX.application(pid), kAXFrontmostAttribute, kCFBooleanTrue) { fronted = true }
        if app.activate(from: .current, options: []) || app.activate(options: []) { fronted = true }
        return fronted
    }

    private func raise(_ w: AXUIElement, pid: pid_t) { Self.raise(w, pid: pid) }

    private static func raise(_ w: AXUIElement, pid: pid_t) {
        if AX.value(w, kAXMinimizedAttribute) as? Bool == true { AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.set(AX.application(pid), kAXMainWindowAttribute, w)
        AX.set(w, kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }

    // MARK: Displays and layouts

    @discardableResult public func moveFocusedWindowToPreviousDisplay() -> Bool { moveToDisplay(forward: false) }
    @discardableResult public func moveFocusedWindowToNextDisplay() -> Bool { moveToDisplay(forward: true) }

    private func moveToDisplay(forward: Bool) -> Bool {
        guard let (w, ax, screens, i) = focusedWindowOnScreen(),
              let j = DisplayGeometry.adjacent(to: i, in: screens.map(\.frame), forward: forward) else { return false }
        let current = DisplayGeometry.appKit(fromAX: ax, primaryMaxY: Self.primaryMaxY)
        let target = DisplayGeometry.rect(moving: current, from: screens[i].visibleFrame, to: screens[j].visibleFrame)
        return AX.setFrame(DisplayGeometry.ax(fromAppKit: target, primaryMaxY: Self.primaryMaxY), of: w)
    }

    @discardableResult public func apply(layout: WindowLayout) -> Bool {
        guard let (w, ax, screens, i) = focusedWindowOnScreen() else { return false }
        let target = DisplayGeometry.frame(for: layout, windowSize: ax.size, in: screens[i].visibleFrame)
        return AX.setFrame(DisplayGeometry.ax(fromAppKit: target, primaryMaxY: Self.primaryMaxY), of: w)
    }

    /// Focused window of the front app, its AX frame, and the screen it mostly sits on. When the front
    /// app offers no window (e.g. a system overlay took focus during a 5-finger gesture), falls back to
    /// the most recently used window.
    private func focusedWindowOnScreen() -> (AXUIElement, CGRect, [NSScreen], Int)? {
        guard AX.trusted else { return nil }
        var window: AXUIElement?
        if let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            window = AX.focusedWindow(pid: app.processIdentifier)
        }
        if window == nil, let (id, pid) = tracker.current() { window = AX.window(id: id, pid: pid) }
        guard let w = window, let ax = AX.frame(of: w) else { return nil }
        let screens = NSScreen.screens
        let rect = DisplayGeometry.appKit(fromAX: ax, primaryMaxY: Self.primaryMaxY)
        func overlap(_ s: NSScreen) -> CGFloat { let r = s.frame.intersection(rect); return r.isNull ? 0 : r.width * r.height }
        guard let i = screens.indices.max(by: { overlap(screens[$0]) < overlap(screens[$1]) }) else { return nil }
        return (w, ax, screens, i)
    }

    private static var primaryMaxY: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }

    // MARK: Cursor

    @discardableResult public func moveCursorToNextDisplay() -> Bool {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        guard let i = screens.firstIndex(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let j = DisplayGeometry.adjacent(to: i, in: screens.map(\.frame), forward: true),
              let number = screens[j].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        let b = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        return CGWarpMouseCursorPosition(CGPoint(x: b.midX, y: b.midY)) == .success
    }
}
