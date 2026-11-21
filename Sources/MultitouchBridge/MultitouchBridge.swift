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
    private var handler: (@Sendable (TouchFrame) -> Void)?
    // Keeping the list alive keeps the devices alive; releasing it silently stops callbacks.
    private var devices: [AnyObject] = []
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    /// Number of multitouch devices found by the last `start`.
    public var deviceCount: Int { lock.withLock { devices.count } }

    public func start(_ onFrame: @escaping @Sendable (TouchFrame) -> Void) {
        lock.withLock { handler = onFrame }
        attach()
    }

    public func stop() {
        detach()
        lock.withLock { handler = nil }
    }

    /// Re-scan devices, e.g. after wake from sleep or when a Magic Trackpad connects.
    public func restart() {
        detach()
        attach()
    }

    fileprivate func deliver(_ frame: TouchFrame) {
        let h = lock.withLock { handler }
        h?(frame)
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

/// Must return 0: on macOS 27 a void-returning callback reportedly suppresses system gestures.
private let contactCallback: MTContactCallbackFunction = { _, touches, count, timestamp, _ in
    var list: [Touch] = []
    list.reserveCapacity(Int(count))
    if let touches {
        for i in 0..<Int(count) {
            let t = touches[i]
            list.append(Touch(
                id: Int(t.identifier),
                x: t.normalized.position.x, y: t.normalized.position.y,
                vx: t.normalized.velocity.x, vy: t.normalized.velocity.y,
                size: t.size, state: Int(t.state)
            ))
        }
    }
    MultitouchBridge.shared.deliver(TouchFrame(timestamp: timestamp, touches: list))
    return 0
}
