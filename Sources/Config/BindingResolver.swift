// SPDX-License-Identifier: GPL-3.0-or-later

import Model

public enum BindingResolver {
    /// The binding to run for a recognised gesture, or nil. Modifiers must match exactly;
    /// a binding limited to the frontmost app beats a global one.
    public static func resolve(_ bindings: [Binding], gesture: Gesture, modifiers: Modifiers, app: String?) -> Binding? {
        let matches = bindings.filter { $0.enabled && $0.gesture == gesture && $0.modifiers == modifiers }
        if let app, let specific = matches.first(where: { $0.apps.contains(app) }) { return specific }
        return matches.first(where: \.isGlobal)
    }
}
