// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum ConfigError: Error, Equatable, LocalizedError, Sendable {
    /// Malformed JSON or a field with a bad value; the message says where.
    case invalid(String)
    case unsupportedVersion(found: Int, supported: Int)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(message): "Invalid configuration: \(message)"
        case let .unsupportedVersion(found, supported):
            "Configuration version \(found) is newer than this app supports (\(supported)). Update OpenGestures."
        case let .unreadable(message): "Cannot access configuration file: \(message)"
        }
    }

    static func describing(_ error: DecodingError) -> ConfigError {
        func path(_ context: DecodingError.Context) -> String {
            var result = ""
            for key in context.codingPath {
                if let i = key.intValue { result += "[\(i)]" } else { result += (result.isEmpty ? "" : ".") + key.stringValue }
            }
            return result
        }
        func located(_ context: DecodingError.Context, _ text: String) -> ConfigError {
            let p = path(context)
            return .invalid(p.isEmpty ? text : "\(p): \(text)")
        }
        switch error {
        case let .dataCorrupted(c):
            // Syntax errors carry JSONSerialization's "... around line L, column C." text.
            let underlying = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return located(c, underlying ?? c.debugDescription)
        case let .keyNotFound(key, c): return located(c, "missing \"\(key.stringValue)\"")
        case let .typeMismatch(_, c), let .valueNotFound(_, c): return located(c, c.debugDescription)
        @unknown default: return .invalid(error.localizedDescription)
        }
    }
}
