// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model

/// The words of the dialog that asks before an action from outside the app may run.
public enum ApprovalPrompt {
    static let maxItems = 8
    static let maxTextLength = 300

    public static func title(count: Int) -> String {
        "Allow \(count) action\(count == 1 ? "" : "s") from the config file?"
    }

    public static let message = "These actions came from the config file, not from this window. They can run commands or open things with OpenGestures' permissions. Allow them only if you wrote or trust them."

    /// One block per binding, with the complete action (long text is cut).
    public static func details(_ bindings: [Binding]) -> String {
        var blocks = bindings.prefix(maxItems).map { b in
            let who = (b.modifiers.symbols.joined() + " " + b.gesture.title).trimmingCharacters(in: .whitespaces)
            return "\(who)\n\(full(b.action))"
        }
        if bindings.count > maxItems { blocks.append("… and \(bindings.count - maxItems) more") }
        return blocks.joined(separator: "\n\n")
    }

    private static func full(_ action: Action) -> String {
        switch action {
        case let .shellScript(s): "Shell script:\n\(cut(s))"
        case let .appleScript(s): "AppleScript:\n\(cut(s))"
        case let .shortcut(name): "Shortcut “\(cut(name))”"
        case let .openFile(path): "Open file \(cut(path))"
        case let .openURL(url): "Open \(cut(url))"
        default: action.summary()
        }
    }

    private static func cut(_ s: String) -> String {
        s.count > maxTextLength ? String(s.prefix(maxTextLength)) + "…" : s
    }
}
