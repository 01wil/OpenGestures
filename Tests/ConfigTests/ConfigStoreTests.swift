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

    // MARK: Symlinks

    private func symlink(to target: URL, relative: Bool = false) throws -> URL {
        let link = dir.appendingPathComponent("link.json")
        if relative {
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path.replacingOccurrences(of: dir.path + "/", with: ""))
        } else {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        }
        return link
    }

    @Test(arguments: [false, true])
    func danglingSymlinkIsWrittenThroughNotReplaced(relative: Bool) throws {
        let target = dir.appendingPathComponent("dotfiles/sub/config.json")
        // Directories are never created for a symlink target: it must already exist.
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let link = try symlink(to: target, relative: relative)

        #expect(try ConfigStore(url: link).load() == .default)

        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(try Configuration.decode(Data(contentsOf: target)) == .default)
    }

    @Test func danglingSymlinkWithUncreatableTargetErrorsAndKeepsLink() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let target = blocker.appendingPathComponent("config.json")
        let link = try symlink(to: target)

        #expect(throws: ConfigError.self) { try ConfigStore(url: link).save(.default) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func watcherSurvivesSymlinkTargetRemovedAndRecreated() async throws {
        let repo = dir.appendingPathComponent("dotfiles", isDirectory: true)
        let target = repo.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Configuration.default.encoded().write(to: target)
        let link = try symlink(to: target)
        let events = Events()
        let watcher = ConfigStore(url: link).watch { events.add($0) }
        defer { watcher.cancel() }

        try FileManager.default.removeItem(at: target)  // git stash
        try await Task.sleep(for: .milliseconds(200))
        var edited = Configuration.default
        edited.settings.sensitivity = 0.9
        try edited.encoded().write(to: target)  // git stash pop
        #expect(await waitUntil { events.all.contains { $0 == .success(edited) } })

        try FileManager.default.removeItem(at: repo)  // whole directory goes
        try await Task.sleep(for: .milliseconds(200))
        edited.settings.sensitivity = 0.1
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try edited.encoded().write(to: target)
        #expect(await waitUntil { events.all.contains { $0 == .success(edited) } })
    }

    // MARK: Binding ids

    @Test func loadFixesMissingAndDuplicateIDsAndWritesThemBack() throws {
        let dup = "0F1E2D3C-0001-4000-8000-000000000001"
        let json = """
        {"bindings": [
          {"id": "\(dup)", "gesture": "tap.3", "action": {"type": "nextWindow"}},
          {"id": "\(dup)", "gesture": "tap.4", "action": {"type": "nextWindow"}},
          {"gesture": "tap.5", "action": {"type": "nextWindow"}}
        ]}
        """
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let first = try store.load()
        #expect(Set(first.bindings.map(\.id)).count == 3)
        #expect(first.bindings[0].id.uuidString == dup)
        #expect(try Configuration.decode(Data(contentsOf: url)) == first)  // written back
        #expect(try store.load() == first)  // stable
    }

    @Test func watcherAlsoNormalizesIDs() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }
        let json = #"{"bindings": [{"gesture": "tap.3", "action": {"type": "nextWindow"}}, {"gesture": "tap.4", "action": {"type": "nextWindow"}}]}"#
        try Data(json.utf8).write(to: url)
        #expect(await waitUntil { (try? Configuration.decode(Data(contentsOf: url)))?.bindings.count == 2
            && (try? String(contentsOf: url, encoding: .utf8))?.contains("\"id\"") == true })
    }

    // MARK: Deleted invalid file

    @Test func deletingInvalidFileRecreatesDefaults() async throws {
        try store.save(.default)
        try Data("{ not json".utf8).write(to: url)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        try FileManager.default.removeItem(at: url)
        #expect(await waitUntil { events.all.last == .success(.default) })
        #expect(try Configuration.decode(Data(contentsOf: url)) == .default)
    }

    @Test func deletingValidFileDoesNothing() async throws {
        try store.save(.default)
        let events = Events()
        let watcher = store.watch { events.add($0) }
        defer { watcher.cancel() }
        try FileManager.default.removeItem(at: url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(events.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct ConfigPermissionTests {
    let dir = try! makeTempDir()

    private func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue & 0o777
    }

    @Test func newConfigIs0600InA0700Directory() throws {
        let url = dir.appendingPathComponent("opengestures/config.json")
        try ConfigStore(url: url).save(.default)
        #expect(try mode(url) == 0o600)
        #expect(try mode(url.deletingLastPathComponent()) == 0o700)
    }

    @Test func overwriteTightensExistingFileAndLeavesDirectoryAlone() throws {
        let url = dir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try ConfigStore(url: url).save(.default)
        #expect(try mode(url) == 0o600)
        #expect(try mode(dir) == 0o755)
    }

    @Test func danglingSymlinkIntoMissingDirectoryErrorsWithoutCreatingIt() throws {
        let target = dir.appendingPathComponent("dotfiles/sub/config.json")
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: ConfigError.self) { try ConfigStore(url: link).save(.default) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("dotfiles").path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    }

    @Test func symlinkTargetKeeps0600AndItsDirectoryMode() throws {
        let repo = dir.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.appendingPathComponent("config.json"))
        try ConfigStore(url: link).save(.default)
        #expect(try mode(repo.appendingPathComponent("config.json")) == 0o600)
        #expect(try mode(repo) == 0o755)
    }
}
