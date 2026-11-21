// SPDX-License-Identifier: GPL-3.0-or-later

import CMultitouch
import Foundation
import Model

/// Streams raw trackpad contacts from the private MultitouchSupport framework as `TouchFrame`s.
///
/// The C callback carries no context pointer, so a single shared instance owns the handler.
/// Frames arrive on a MultitouchSupport thread; the handler must be quick and thread-safe.
public final class MultitouchBridge: @unchecked Sendable {
    public static let shared = MultitouchBridge()

    private let lock = NSLock()
    private var handler: (@Sendable (_ device: Int, TouchFrame) -> Void)?
    // Keeping the list alive keeps the devices alive; releasing it silently stops callbacks.
    private var devices: [AnyObject] = []
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    /// Number of multitouch devices found by the last `start`.
    public var deviceCount: Int { lock.withLock { devices.count } }

    public func start(_ onFrame: @escaping @Sendable (TouchFrame) -> Void) {
        start(perDevice: { _, frame in onFrame(frame) })
    }

    /// `device` identifies the trackpad for as long as it stays attached; feed each to its own recogniser.
    public func start(perDevice onFrame: @escaping @Sendable (_ device: Int, TouchFrame) -> Void) {
        lock.withLock { handler = onFrame }
        attach()
    }

    public func stop() {
        detach()
        lock.withLock { handler = nil }
    }

    /// Re-scan devices, e.g. after wake from sleep or when a Magic Trackpad connects. `between` runs once
    /// the old devices are stopped and before the new ones start: a new device can reuse a freed device's
    /// address, so per-device state keyed by it must be dropped exactly there.
    public func restart(between: () -> Void = {}) {
        detach()
        between()
        attach()
    }

    fileprivate func deliver(device: Int, _ frame: TouchFrame) {
        let h = lock.withLock { handler }
        h?(device, frame)
    }

    private func attach() {
        let list = MTDeviceCreateList().takeRetainedValue() as [AnyObject]
        for device in list {
            let ref = Unmanaged.passUnretained(device).toOpaque()
            MTRegisterContactFrameCallback(ref, contactCallback)
            MTDeviceStart(ref, 0)
        }
        lock.withLock { devices = list }
    }

    private func detach() {
        let old = lock.withLock { () -> [AnyObject] in
            defer { devices = [] }
            return devices
        }
        for device in old {
            MTDeviceStop(Unmanaged.passUnretained(device).toOpaque())
        }
    }
}

extension MultitouchBridge {
    /// Contacts per frame accepted from the framework; a bogus count must not become a huge read.
    static let maxTouches = 32

    /// Converts a raw frame, dropping touches with non-finite values (they would trap later conversions).
    static func touches(from touches: UnsafePointer<MTTouch>?, count: Int32) -> [Touch] {
        guard let touches, count > 0 else { return [] }
        var list: [Touch] = []
        for i in 0..<Int(min(Int(count), maxTouches)) {
            let t = touches[i]
            let values = [t.normalized.position.x, t.normalized.position.y, t.normalized.velocity.x, t.normalized.velocity.y, t.size]
            guard values.allSatisfy(\.isFinite) else { continue }
            list.append(Touch(
                id: Int(t.identifier),
                x: t.normalized.position.x, y: t.normalized.position.y,
                vx: t.normalized.velocity.x, vy: t.normalized.velocity.y,
                size: t.size, state: Int(t.state)
            ))
        }
        return list
    }
}

/// Must return 0: on macOS 27 a void-returning callback reportedly suppresses system gestures.
private let contactCallback: MTContactCallbackFunction = { device, touches, count, timestamp, _ in
    MultitouchBridge.shared.deliver(device: Int(bitPattern: device),
                                    TouchFrame(timestamp: timestamp, touches: MultitouchBridge.touches(from: touches, count: count)))
    return 0
}
