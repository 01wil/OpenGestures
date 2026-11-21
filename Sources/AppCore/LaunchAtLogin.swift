// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum LoginItemStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval
}

/// `SMAppService.mainApp` in the app; a fake in tests.
public protocol LoginItemService: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Keeps the login item in line with the setting. It only acts when the setting changes (or on `retry`),
/// and exposes the real status and the last failure for the UI.
public struct LaunchAtLogin {
    private let service: any LoginItemService
    private var lastWanted: Bool?
    public private(set) var status: LoginItemStatus
    public private(set) var error: String?

    public init(_ service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    public mutating func sync(wanted: Bool, retry: Bool = false) {
        defer { status = service.status }
        guard retry || wanted != lastWanted else { return }
        lastWanted = wanted
        error = nil
        guard wanted != (service.status != .notRegistered) else { return }
        do {
            if wanted { try service.register() } else { try service.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public mutating func refresh() { status = service.status }
}
