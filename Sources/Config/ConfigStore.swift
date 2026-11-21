// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL()) {
        self.url = url
    }

    /// `$XDG_CONFIG_HOME/opengestures/config.json`, else `~/.config/opengestures/config.json`.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return base.appendingPathComponent("opengestures/config.json")
    }

    /// A missing file is created from the default configuration. An invalid file throws and is left untouched.
    /// Bindings without an id, or repeating one, get a unique id which is written back once.
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try save(.default)
            return .default
        }
        return try parse(read()).config
    }

    /// Atomic. A symlink (e.g. into a dotfiles repo) is followed to its destination, even a missing one, and kept.
    public func save(_ configuration: Configuration) throws {
        let target = Self.resolved(url)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try configuration.encoded().write(to: target, options: .atomic)
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
    }

    /// Follows a chain of symlinks without requiring the final destination to exist.
    static func resolved(_ url: URL) -> URL {
        var current = url
        for _ in 0..<32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { break }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        return current
    }

    /// Decodes `data` and gives every binding a unique id (the first of a repeated id keeps it; ids
    /// derive from the position so they are the same on every load). Writes the result back if any changed.
    func parse(_ data: Data) throws -> (config: Configuration, encoded: Data) {
        var config = try Configuration.decode(data)
        let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["bindings"] as? [[String: Any]] ?? []
        var seen = Set<UUID>()
        var changed = false
        for i in config.bindings.indices {
            let hasID = i < raw.count && raw[i]["id"] is String
            if hasID, seen.insert(config.bindings[i].id).inserted { continue }
            var n = i
            var id: UUID
            repeat {
                id = UUID(uuidString: String(format: "0F1E2D3C-B1D0-4000-8000-%012X", n))!
                n += config.bindings.count
            } while seen.contains(id)
            seen.insert(id)
            config.bindings[i].id = id
            changed = true
        }
        let encoded = try config.encoded()
        if changed, (try? save(config)) != nil { return (config, encoded) }
        return (config, data)
    }

    /// Calls `onChange` (on a background queue) whenever the file's content changes, with the new
    /// configuration or the error; the caller keeps its last good configuration on failure.
    /// Our own `save` triggers it too.
    public func watch(_ onChange: @escaping @Sendable (Result<Configuration, ConfigError>) -> Void) -> ConfigWatcher {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return ConfigWatcher(store: self, handler: onChange)
    }

    func read() throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw ConfigError.unreadable(error.localizedDescription) }
    }
}

/// Watches the directories (editors that rename a new file over the old one, new symlinks, and for a
/// symlinked config the target's directory, which may vanish and reappear) and the file itself (in-place
/// writes), re-arming everything after each event because inodes may have changed.
public final class ConfigWatcher: @unchecked Sendable {
    private let store: ConfigStore
    private var url: URL { store.url }
    private let handler: @Sendable (Result<Configuration, ConfigError>) -> Void
    private let queue = DispatchQueue(label: "opengestures.config-watcher")
    // Everything below is touched only on `queue`.
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastData: Data?
    private var lastWasError = false
    private var pending: DispatchWorkItem?
    private var cancelled = false

    private static let debounce: DispatchTimeInterval = .milliseconds(50)

    init(store: ConfigStore, handler: @escaping @Sendable (Result<Configuration, ConfigError>) -> Void) {
        self.store = store
        self.handler = handler
        queue.sync {
            lastData = try? Data(contentsOf: store.url)
            lastWasError = lastData.map { (try? Configuration.decode($0)) == nil } ?? false
            arm()
        }
    }

    public func cancel() {
        queue.sync {
            cancelled = true
            pending?.cancel()
            (sources + [fileSource].compactMap { $0 }).forEach { $0.cancel() }
            sources = []
            fileSource = nil
        }
    }

    deinit { cancel() }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        var watched = Set<String>()
        for dir in [url, ConfigStore.resolved(url)].map({ $0.deletingLastPathComponent() }) {
            // A removed directory is watched through its nearest existing ancestor.
            var dir = dir
            while !FileManager.default.fileExists(atPath: dir.path), dir.path != "/" { dir = dir.deletingLastPathComponent() }
            if watched.insert(dir.path).inserted, let s = makeSource(path: dir.path, mask: [.write, .rename, .delete, .link]) { sources.append(s) }
        }
        fileSource?.cancel()
        fileSource = makeSource(path: url.path, mask: [.write, .extend, .delete, .rename, .link])
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }

    private func reload() {
        guard !cancelled else { return }
        arm()
        guard var data = try? Data(contentsOf: url) else {
            // Missing mid-replace: wait for the next event. But deleting an invalid file means "start over".
            guard lastWasError, (try? store.save(.default)) != nil, let defaults = try? Configuration.default.encoded() else { return }
            lastData = defaults
            lastWasError = false
            handler(.success(.default))
            return
        }
        guard data != lastData else { return }
        let result = Result { try store.parse(data) }
        if case let .success(parsed) = result { data = parsed.encoded }
        lastData = data
        lastWasError = (try? result.get()) == nil
        handler(result.map(\.config).mapError { $0 as? ConfigError ?? .invalid("\($0)") })
    }
}
