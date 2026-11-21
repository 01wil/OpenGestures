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
    private var memory = RestoreMemory<CGWindowID>()
    private let watcher = RestoreWatcher()

    public init() {
        watcher.onEvent = { [weak self] id, event in self?.windowEvent(id, event) }
    }

    public func start() { tracker.start() }

    /// Re-attaches focus tracking, e.g. once Accessibility has been granted.
    public func restart() {
        tracker.stop()
        tracker.start()
    }

    // MARK: Focus

    @discardableResult public func focusPreviousWindow() -> Bool { focus(tracker.previous()) }
    @discardableResult public func focusNextWindow() -> Bool { focus(tracker.next()) }

    private func focus(_ target: (id: CGWindowID, pid: pid_t)?) -> Bool {
        guard AX.trusted, let (id, pid) = target, let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden { app.unhide() }
        if let w = AX.window(id: id, pid: pid) {
            raise(w, pid: pid)
            return activate(app, pid: pid)
        }
        // Not listed by AX: another Space. Public API cannot front it, so use the window-server path, then
        // wait for the Space switch to finish before raising and activating (activating earlier can bring
        // another window of the app forward).
        guard PrivateFront.front(windowID: id, pid: pid) else { return activate(app, pid: pid) }
        afterSpaceSwitch { [weak self] in
            if let w = AX.window(id: id, pid: pid) { Self.raise(w, pid: pid) }
            self?.activate(app, pid: pid)
        }
        return true
    }

    /// Runs `body` once, on the next Space change or after a 1.5 s deadline, whichever comes first.
    private func afterSpaceSwitch(_ body: @escaping @MainActor () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        var token: NSObjectProtocol?
        var done = false
        let finish: @MainActor () -> Void = {
            guard !done else { return }
            done = true
            if let token { center.removeObserver(token) }
            body()
        }
        token = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { finish() } }
    }

    @discardableResult
    private func activate(_ app: NSRunningApplication, pid: pid_t) -> Bool {
        var fronted = false
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
        if let id = AX.windowID(w) { forget(id) }
        return AX.setFrame(DisplayGeometry.ax(fromAppKit: target, primaryMaxY: Self.primaryMaxY), of: w)
    }

    /// Applies the layout, or, when the window already sits at it and we saved its earlier frame, puts
    /// that frame back.
    @discardableResult public func apply(layout: WindowLayout) -> Bool {
        guard let (w, ax, screens, i) = focusedWindowOnScreen() else { return false }
        let target = DisplayGeometry.ax(fromAppKit: DisplayGeometry.frame(for: layout, windowSize: ax.size, in: screens[i].visibleFrame),
                                        primaryMaxY: Self.primaryMaxY)
        guard let id = AX.windowID(w) else { return AX.setFrame(target, of: w) }
        switch memory.toggle(id, current: ax, target: target) {
        case .restore(let original):
            watcher.unwatch(id)
            return AX.setFrame(original, of: w)
        case .apply:
            let ok = AX.setFrame(target, of: w)
            if ok, memory.original(of: id) != nil {
                memory.placed(id, at: AX.frame(of: w) ?? target)
                watcher.watch(id, w)
            } else {
                forget(id)
            }
            return ok
        }
    }

    private func forget(_ id: CGWindowID) {
        memory.forget(id)
        watcher.unwatch(id)
    }

    /// The user resizing or closing a window drops its saved frame; dragging it with the left button
    /// down restores the saved size under the cursor. Our own setFrame reports the size we placed.
    private func windowEvent(_ id: CGWindowID, _ event: RestoreWatcher.Event) {
        guard event != .closed, let w = watcher.element(for: id), let frame = AX.frame(of: w) else { return forget(id) }
        if memory.userResized(id, to: frame.size) { return forget(id) }
        guard event == .moved, NSEvent.pressedMouseButtons & 1 != 0, let original = memory.original(of: id) else { return }
        let maxY = Self.primaryMaxY
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let target = DisplayGeometry.restoredFrame(dragging: frame, restoreSize: original.size,
                                                   pointer: CGPoint(x: mouse.x, y: maxY - mouse.y),
                                                   in: DisplayGeometry.ax(fromAppKit: visible, primaryMaxY: maxY))
        forget(id)
        AX.setFrame(target, of: w)
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
