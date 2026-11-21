// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import Model
@testable import Config

/// Collects watcher callbacks from the watcher's queue for the test to poll.
final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Result<Configuration, ConfigError>] = []
    func add(_ r: Result<Configuration, ConfigError>) { lock.withLock { items.append(r) } }
    var all: [Result<Configuration, ConfigError>] { lock.withLock { items } }
}

/// Polls until `condition` holds or the deadline passes.
func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("og-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

@Suite struct ConfigStoreTests {
    let dir: URL
    let url: URL
    let store: ConfigStore

    init() throws {
        dir = try makeTempDir()
        url = dir.appendingPathComponent("nested/config.json")
        store = ConfigStore(url: url)
    }

    @Test func defaultURLUsesHomeConfigDir() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(ConfigStore.defaultURL(environment: [:], home: home).path == "/Users/x/.config/opengestures/config.json")
        #expect(ConfigStore.defaultURL(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).path == "/xdg/opengestures/config.json")
        #expect(ConfigStore.defaultURL(environment: ["XDG_CONFIG_HOME": ""], home: home).path == "/Users/x/.config/opengestures/config.json")
    }

    @Test func missingFileWritesAndReturnsDefault() throws {
        #expect(try store.load() == .default)
        #expect(try Configuration.decode(Data(contentsOf: url)) == .default)
    }

    @Test func saveThenLoadRoundTrips() throws {
        var c = Configuration.default
        c.settings.sensitivity = 0.8
        c.bindings.removeFirst()
        try store.save(c)
        #expect(try store.load() == c)
    }

    @Test func invalidFileThrowsAndIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data(#"{"bindings": [{"gesture": "nope", "action": {"type": "nextWindow"}}]}"#.utf8)
        try bad.write(to: url)
        #expect(throws: ConfigError.self) { try store.load() }
        #expect(try Data(contentsOf: url) == bad)
    }

    @Test func saveWritesThroughSymlink() throws {
        let repo = dir.appendingPathComponent("dotfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let target = repo.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: target)
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try ConfigStore(url: link).save(.default)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try Configuration.decode(Data(contentsOf: target)) == .default)
    }

    @Test func watcherReportsInPlaceEdit() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }

        var edited = Configuration.default
        edited.settings.enabled = false
        try edited.encoded().write(to: url)  // in place, same inode
        #expect(await waitUntil { events.all.contains { $0 == .success(edited) } })
    }

    @Test func watcherReportsEditorStyleReplace() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }

        var edited = Configuration.default
        edited.settings.launchAtLogin = true
        let temp = url.deletingLastPathComponent().appendingPathComponent("config.json.swp")
        try edited.encoded().write(to: temp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        #expect(await waitUntil { events.all.contains { $0 == .success(edited) } })

        // A second replace still works: the watcher re-attached to the new file.
        edited.settings.sensitivity = 0.1
        try edited.encoded().write(to: temp)
        try FileManager.default.moveItem(at: temp, to: url.deletingLastPathComponent().appendingPathComponent("tmp2"))
        _ = try FileManager.default.replaceItemAt(url, withItemAt: url.deletingLastPathComponent().appendingPathComponent("tmp2"))
        #expect(await waitUntil { events.all.contains { $0 == .success(edited) } })
    }

    @Test func watcherReportsErrorThenRecovers() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }

        try Data("{ not json".utf8).write(to: url)
        #expect(await waitUntil { events.all.contains { if case .failure = $0 { true } else { false } } })
        #expect(try Data(contentsOf: url) == Data("{ not json".utf8))

        var fixed = Configuration.default
        fixed.settings.showMenuBarIcon = false
        try fixed.encoded().write(to: url)
        #expect(await waitUntil { events.all.last == .success(fixed) })
    }

    @Test func watcherStaysQuietWithoutChanges() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(events.all.isEmpty)
    }
}
