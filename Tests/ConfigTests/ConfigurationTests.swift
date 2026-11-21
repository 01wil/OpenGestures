// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import Model
@testable import Config

@Suite struct ConfigurationTests {
    @Test func defaultRoundTripsUnchanged() throws {
        let data = try Configuration.default.encoded()
        let decoded = try Configuration.decode(data)
        #expect(decoded == Configuration.default)
        #expect(try decoded.encoded() == data)
    }

    @Test func defaultHasTheFourShippedBindings() {
        let b = Configuration.default.bindings
        #expect(b.map(\.gesture.id) == ["swipe.4.left", "swipe.4.right", "swipe.4.left", "swipe.4.right"])
        #expect(b.map(\.modifiers) == [[], [], .command, .command])
        #expect(b.map(\.action) == [.previousWindow(), .nextWindow(), .previousDisplay, .nextDisplay])
        #expect(b.allSatisfy { $0.isGlobal && $0.enabled && $0.name != nil })
        #expect(Set(b.map(\.id)).count == 4)
        #expect(Configuration.default.version == Configuration.currentVersion)
    }

    @Test func encodingIsPrettyPrintedAndSorted() throws {
        let text = String(decoding: try Configuration.default.encoded(), as: UTF8.self)
        #expect(text.contains("\n  \"bindings\""))
        let keys = ["bindings", "settings", "version"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(keys == keys.sorted())
        #expect(!text.contains("\\/"))
    }

    @Test func missingOptionalFieldsUseDefaults() throws {
        let c = try Configuration.decode(Data("{}".utf8))
        #expect(c.version == 1)
        #expect(c.settings == Settings())
        #expect(c.bindings.isEmpty)
        let partial = try Configuration.decode(Data(#"{"settings": {"sensitivity": 0.9}}"#.utf8))
        #expect(partial.settings.sensitivity == 0.9)
        #expect(partial.settings.enabled)
        #expect(partial.settings.showMenuBarIcon)
        #expect(!partial.settings.launchAtLogin)
    }

    @Test func unversionedAndOlderFilesMigrateToCurrent() throws {
        let old = #"{"version": 0, "bindings": [{"gesture": "tap.3", "action": {"type": "nextWindow"}}]}"#
        let c = try Configuration.decode(Data(old.utf8))
        #expect(c.version == Configuration.currentVersion)
        #expect(c.bindings.count == 1)
    }

    @Test func newerVersionIsRejectedClearly() {
        let error = #expect(throws: ConfigError.self) {
            try Configuration.decode(Data(#"{"version": 99}"#.utf8))
        }
        #expect(error == .unsupportedVersion(found: 99, supported: 1))
        #expect(error?.localizedDescription.contains("99") == true)
    }

    @Test func badFieldErrorNamesThePath() {
        let json = #"{"bindings": [{"gesture": "swipe.9.left", "action": {"type": "nextWindow"}}]}"#
        let error = #expect(throws: ConfigError.self) { try Configuration.decode(Data(json.utf8)) }
        let message = error?.localizedDescription ?? ""
        #expect(message.contains("bindings[0].gesture"))
        #expect(message.contains("swipe.9.left"))
    }

    @Test func syntaxErrorReportsLine() {
        let error = #expect(throws: ConfigError.self) {
            try Configuration.decode(Data("{\n  \"version\": 1,\n  oops\n}".utf8))
        }
        #expect(error?.localizedDescription.contains("line 3") == true)
    }
}
