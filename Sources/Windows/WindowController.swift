// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import AppKit
import Model

/// The window operations the Actions module calls. All return false when they could not act (no
/// Accessibility permission, no target, single display); none throws, blocks long, or moves anything
/// outside the intended window / cursor. Call `start()` once; main actor only.
@MainActor
public final class WindowController {
    private let tracker = WindowTracker()

    public init() {}

    public func start() { tracker.start() }

    // MARK: Focus

    @discardableResult public func focusPreviousWindow() -> Bool { focus(tracker.previous()) }
    @discardableResult public func focusNextWindow() -> Bool { focus(tracker.next()) }

    private func focus(_ target: (id: CGWindowID, pid: pid_t)?) -> Bool {
        guard AX.trusted, let (id, pid) = target, let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden { app.unhide() }
        if let w = AX.window(id: id, pid: pid) {
            app.activate(from: .current, options: [])
            raise(w, pid: pid)
        } else {
            // Not listed by AX: another Space. Public API cannot front it, so use the window-server path.
            PrivateFront.front(windowID: id, pid: pid)
            app.activate(from: .current, options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let w = AX.window(id: id, pid: pid) { Self.raise(w, pid: pid) }
            }
        }
        return true
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

    /// Focused window of the front app, its AX frame, and the screen it mostly sits on.
    private func focusedWindowOnScreen() -> (AXUIElement, CGRect, [NSScreen], Int)? {
        guard AX.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let w = AX.focusedWindow(pid: app.processIdentifier), let ax = AX.frame(of: w) else { return nil }
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
