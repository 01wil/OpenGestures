// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import AppCore

final class FakeLoginItem: LoginItemService, @unchecked Sendable {
    var status: LoginItemStatus
    var failure: (any Error)?
    var calls: [String] = []
    init(_ status: LoginItemStatus = .notRegistered) { self.status = status }
    func register() throws {
        calls.append("register")
        if let failure { throw failure }
        status = .enabled
    }
    func unregister() throws {
        calls.append("unregister")
        if let failure { throw failure }
        status = .notRegistered
    }
}

struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }

@Suite struct LaunchAtLoginTests {
    @Test func registersOnlyWhenTheSettingChanges() {
        let service = FakeLoginItem()
        var login = LaunchAtLogin(service)
        login.sync(wanted: true)
        login.sync(wanted: true)
        login.sync(wanted: true)
        #expect(service.calls == ["register"])
        login.sync(wanted: false)
        login.sync(wanted: false)
        #expect(service.calls == ["register", "unregister"])
    }

    @Test func firstSyncMatchesRealStatusWithoutCalls() {
        let service = FakeLoginItem(.enabled)
        var login = LaunchAtLogin(service)
        login.sync(wanted: true)
        #expect(service.calls.isEmpty)
        #expect(login.status == .enabled)
    }

    @Test func failureIsKeptAndNotRepeatedUntilRetry() {
        let service = FakeLoginItem()
        service.failure = Boom()
        var login = LaunchAtLogin(service)
        login.sync(wanted: true)
        login.sync(wanted: true)
        #expect(service.calls == ["register"])
        #expect(login.error == "boom")
        #expect(login.status == .notRegistered)  // the toggle shows the truth

        service.failure = nil
        login.sync(wanted: true, retry: true)
        #expect(service.calls == ["register", "register"])
        #expect(login.error == nil)
        #expect(login.status == .enabled)
    }

    @Test func requiresApprovalIsReportedAndNotReRegistered() {
        let service = FakeLoginItem(.requiresApproval)
        var login = LaunchAtLogin(service)
        login.sync(wanted: true)
        #expect(service.calls.isEmpty)
        #expect(login.status == .requiresApproval)
    }

    @Test func refreshPicksUpApprovalGrantedInSystemSettings() {
        let service = FakeLoginItem(.requiresApproval)
        var login = LaunchAtLogin(service)
        login.sync(wanted: true)
        service.status = .enabled
        login.refresh()
        #expect(login.status == .enabled)
    }
}
