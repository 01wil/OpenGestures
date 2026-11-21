// SPDX-License-Identifier: GPL-3.0-or-later

import Actions
import AppCore
import AppKit
import IOKit
import Model
import MultitouchBridge
import Windows

/// Trackpad frames → per-device recognisers → binding → action. Frames are processed on the
/// MultitouchSupport thread; only recognised gestures (rare) hop to the main actor.
@MainActor
final class Engine {
    private let pipeline = GesturePipeline()
    private let windows = WindowController()
    private let report: @MainActor (_ message: String, _ kind: String) -> Void
    private lazy var runner = ActionRunner(windows: WindowCommandsAdapter(controller: windows), onError: { [weak self] error in
        Task { @MainActor in self?.report(error.message, error.kind) }
    })
    private var bindings: [Binding] = []
    private var enabled = false
    private var running = false
    private var recorder: ((Gesture, Modifiers) -> Void)?
    private var notificationPort: IONotificationPortRef?
    private var pendingRestart: DispatchWorkItem?

    init(report: @escaping @MainActor (_ message: String, _ kind: String) -> Void) {
        self.report = report
    }

    func start() {
        windows.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.restartSoon() }
        }
        watchDevices()
        updateRunning()
    }

    /// Accessibility was just granted: the window tracker needs AX to follow focus.
    func accessibilityGranted() {
        windows.restart()
    }

    func configure(bindings: [Binding], enabled: Bool, sensitivity: Double) {
        self.bindings = bindings
        self.enabled = enabled
        pipeline.setSensitivity(sensitivity)
        updateRunning()
    }

    /// The next recognised gesture goes to `completion` instead of running a binding. Works while paused.
    func record(_ completion: @escaping (Gesture, Modifiers) -> Void) {
        recorder = completion
        updateRunning()
    }

    func cancelRecording() {
        recorder = nil
        updateRunning()
    }

    private func updateRunning() {
        let wanted = enabled || recorder != nil
        guard wanted != running else { return }
        running = wanted
        if wanted {
            let pipeline = pipeline
            MultitouchBridge.shared.start(perDevice: { device, frame in
                let events = pipeline.process(device: device, frame: frame)
                guard !events.isEmpty else { return }
                let modifiers = Modifiers(CGEventSource.flagsState(.combinedSessionState))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.handle(events, modifiers: modifiers) }
                }
            })
            log.info("engine started, \(MultitouchBridge.shared.deviceCount) trackpad(s)")
        } else {
            MultitouchBridge.shared.stop()
            pipeline.reset()
            log.info("engine stopped")
        }
    }

    private func handle(_ events: [GestureEvent], modifiers: Modifiers) {
        for event in events {
            if let recorder {
                self.recorder = nil
                updateRunning()
                recorder(event.gesture, modifiers)
                continue
            }
            guard enabled else { return }
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let dispatch = Dispatcher.dispatch(event, bindings: bindings, modifiers: modifiers, app: app)
            // Sliding gestures send a stream of deltas; log only the discrete ones.
            if event.delta == nil {
                // Never the action itself: scripts, URLs and paths stay out of the log.
                let what: String = switch dispatch {
                case let .run(action)?: action.kind.rawValue
                case .adjust?: "adjust"
                case nil: "no binding"
                }
                log.info("gesture \(event.gesture.id, privacy: .public) → \(what, privacy: .public)")
            }
            switch dispatch {
            case let .run(action)?: runner.run(action)
            case let .adjust(target, delta)?: runner.adjust(target, delta: delta)
            case nil: break
            }
        }
    }

    // MARK: Device changes

    /// Debounced: a device that just appeared may not deliver frames yet, and wake sends several events.
    private func restartSoon() {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { self.restart() } }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func restart() {
        guard running else { return }
        pipeline.reset()
        MultitouchBridge.shared.restart()
        log.info("engine restarted, \(MultitouchBridge.shared.deviceCount) trackpad(s)")
    }

    /// IOKit tells us when a multitouch device (e.g. a Magic Trackpad) appears or disappears.
    private func watchDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            Engine.drain(iterator)
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<Engine>.fromOpaque(context).takeUnretainedValue().restartSoon() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, context, &iterator)
            // Draining arms the notification; the devices already present need no restart.
            Engine.drain(iterator)
        }
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }
}

/// Windows.WindowController reports failure with false; the action runner expects a throw.
struct WindowCommandsAdapter: WindowCommands {
    let controller: WindowController

    private func perform(_ failure: String, _ body: @escaping @MainActor @Sendable (WindowController) -> Bool) throws {
        let controller = controller
        let ok = Thread.isMainThread
            ? MainActor.assumeIsolated { body(controller) }
            : DispatchQueue.main.sync { MainActor.assumeIsolated { body(controller) } }
        guard ok else {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            log.error("window action failed, frontmost app: \(front, privacy: .public)")
            throw ActionError.failed(AXIsProcessTrusted() ? failure : "OpenGestures needs Accessibility access to control windows (Settings › Permissions).")
        }
    }

    func focusPreviousWindow() throws { try perform("No previous window to switch to.") { $0.focusPreviousWindow() } }
    func focusNextWindow() throws { try perform("No next window to switch to.") { $0.focusNextWindow() } }
    func moveFocusedWindowToPreviousDisplay() throws { try perform("No other display to move the window to.") { $0.moveFocusedWindowToPreviousDisplay() } }
    func moveFocusedWindowToNextDisplay() throws { try perform("No other display to move the window to.") { $0.moveFocusedWindowToNextDisplay() } }
    func apply(layout: WindowLayout) throws { try perform("No window to arrange.") { $0.apply(layout: layout) } }
    func moveCursorToNextDisplay() throws { try perform("No other display to move the pointer to.") { $0.moveCursorToNextDisplay() } }
}
