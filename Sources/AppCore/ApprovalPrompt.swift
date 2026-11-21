// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model

/// The words of the dialog that asks before an action from outside the app may run.
public enum ApprovalPrompt {
    public static func title(count: Int) -> String {
        "Allow \(count) action\(count == 1 ? "" : "s") from the config file?"
    }

    public static let message = "These actions came from the config file, not from this window. They can run commands or open things with OpenGestures' permissions. Allow them only if you wrote or trust them."

    /// One block per binding with its complete action and scope, never shortened: Allow approves all of it.
    public static func details(_ bindings: [Binding]) -> String {
        bindings.map { b in
            let who = (b.modifiers.symbols.joined() + " " + b.gesture.title).trimmingCharacters(in: .whitespaces)
            let scope = b.apps.isEmpty ? "" : " in \(visible(b.apps.joined(separator: ", ")))"
            return "\(who)\(scope)\n\(full(b.action))"
        }.joined(separator: "\n\n")
    }

    private static func full(_ action: Action) -> String {
        switch action {
        case let .shellScript(s): "Shell script:\n\(visible(s))"
        case let .appleScript(s): "AppleScript:\n\(visible(s))"
        case let .shortcut(name): "Shortcut “\(visible(name))”"
        case let .openFile(path): "Open file \(visible(path))"
        case let .openURL(url): "Open \(visible(url))"
        default: action.summary()
        }
    }

    /// Shows invisible characters (direction overrides, zero-width and other format or control characters, line
    /// and paragraph separators) as escapes like \u{202E}, so the text shown is the text that runs.
    static func visible(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control where scalar != "\n" && scalar != "\t", .format, .lineSeparator, .paragraphSeparator:
                let hex = String(scalar.value, radix: 16, uppercase: true)
                out += "\\u{\(String(repeating: "0", count: max(0, 4 - hex.count)) + hex)}"
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
