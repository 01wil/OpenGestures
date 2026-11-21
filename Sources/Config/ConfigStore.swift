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
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try save(.default)
            return .default
        }
        return try Configuration.decode(read())
    }

    /// Atomic. If `url` is a symlink (e.g. into a dotfiles repo) the target is replaced and the link kept.
    public func save(_ configuration: Configuration) throws {
        let target = url.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try configuration.encoded().write(to: target, options: .atomic)
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
    }

    /// Calls `onChange` (on a background queue) whenever the file's content changes, with the new
    /// configuration or the error; the caller keeps its last good configuration on failure.
    /// Our own `save` triggers it too.
    public func watch(_ onChange: @escaping @Sendable (Result<Configuration, ConfigError>) -> Void) -> ConfigWatcher {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return ConfigWatcher(url: url, handler: onChange)
    }

    func read() throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw ConfigError.unreadable(error.localizedDescription) }
    }
}

/// Watches both the directory (editors that rename a new file over the old one, new symlinks) and the file
/// itself (in-place writes), re-attaching to the file after every event because its inode may have changed.
public final class ConfigWatcher: @unchecked Sendable {
    private let url: URL
    private let handler: @Sendable (Result<Configuration, ConfigError>) -> Void
    private let queue = DispatchQueue(label: "opengestures.config-watcher")
    // Everything below is touched only on `queue`.
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastData: Data?
    private var pending: DispatchWorkItem?
    private var cancelled = false

    private static let debounce: DispatchTimeInterval = .milliseconds(50)

    init(url: URL, handler: @escaping @Sendable (Result<Configuration, ConfigError>) -> Void) {
        self.url = url
        self.handler = handler
        queue.sync {
            lastData = try? Data(contentsOf: url)
            if let s = makeSource(path: url.deletingLastPathComponent().path, mask: [.write, .rename, .delete, .link]) { sources.append(s) }
            attachFile()
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

    private func attachFile() {
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
        attachFile()
        // Missing mid-replace: wait for the next event rather than reporting an error.
        guard let data = try? Data(contentsOf: url), data != lastData else { return }
        lastData = data
        handler(Result { try Configuration.decode(data) }.mapError { $0 as? ConfigError ?? .invalid("\($0)") })
    }
}
