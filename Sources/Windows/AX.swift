// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
import ApplicationServices
import AppKit

/// Thin Accessibility helpers. Every call is a no-op / nil without the permission and carries a short
/// messaging timeout so a hung target app cannot stall us.
enum AX {
    static let timeout: Float = 0.25
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Elements without their own timeout (windows, found via an app element) fall back to this one.
    private static let systemWide: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }()

    static func application(_ pid: pid_t) -> AXUIElement {
        _ = systemWide
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, timeout)
        return e
    }

    static func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    @discardableResult
    static func set(_ e: AXUIElement, _ name: String, _ v: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(e, name as CFString, v) == .success
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        guard trusted else { return nil }
        let app = application(pid)
        return element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    /// The app's window with this WindowServer id. Only windows on the current Space are listed by AX.
    static func window(id: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard trusted, let list = value(application(pid), kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return list.first { windowID($0) == id }
    }

    // Private: maps an AX window to its CGWindowID. Resolved lazily; nil when the symbol is missing.
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(p, to: GetWindow.self)
    }()

    static func windowID(_ e: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(e, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// AX frame (top-left origin).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), let s = value(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Size, position, size: the first size lets the move land on a smaller display, the last
    /// corrects a size the system clamped on the way.
    @discardableResult
    static func setFrame(_ r: CGRect, of window: AXUIElement) -> Bool {
        var size = r.size, origin = r.origin
        guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &origin) else { return false }
        let a = set(window, kAXSizeAttribute, s)
        let b = set(window, kAXPositionAttribute, p)
        set(window, kAXSizeAttribute, s)
        return a && b
    }
}

/// WindowServer queries (public API).
enum WindowList {
    struct Item { let id: CGWindowID; let pid: pid_t }

    /// Normal-layer windows, front to back when `onScreenOnly`. `.optionAll` also lists other Spaces
    /// and minimised windows. Tiny windows (status items, shadows) are ignored.
    static func items(onScreenOnly: Bool) -> [Item] {
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 50, (b["Height"] ?? 0) >= 50 else { return nil }
            return Item(id: id, pid: pid)
        }
    }
}

/// Private window-server path (same recipe as yabai/AltTab/Vorssaint) to front a window on another Space.
/// Used only when AX cannot see the window; both symbols are nil-checked.
enum PrivateFront {
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private typealias SetFront = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> CGError

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }

    @discardableResult
    static func front(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getPSN = symbol("GetProcessForPID", as: GetProcessForPID.self),
              let setFront = symbol("_SLPSSetFrontProcessWithOptions", as: SetFront.self) else { return false }
        var psn: (UInt32, UInt32) = (0, 0)
        return withUnsafeMutablePointer(to: &psn) { p in
            getPSN(pid, p) == 0 && setFront(p, windowID, 0x200) == .success
        }
    }
}
