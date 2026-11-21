// SPDX-License-Identifier: GPL-3.0-or-later

import Model

public struct ValidationWarning: Equatable, Sendable {
    public enum Kind: Sendable { case duplicateTrigger, adjustOnDiscreteGesture, discreteActionOnContinuousGesture }

    public var kind: Kind
    public var bindingIDs: [Binding.ID]
    public var message: String
}

public enum Validator {
    /// Problems the editor can show next to the offending bindings. None of them stop the config loading.
    public static func warnings(for bindings: [Binding]) -> [ValidationWarning] {
        var result: [ValidationWarning] = []
        for (i, a) in bindings.enumerated() {
            if a.enabled {
                switch (a.gesture.isContinuous, a.action) {
                case (false, .adjust):
                    result.append(.init(kind: .adjustOnDiscreteGesture, bindingIDs: [a.id],
                                        message: "\(label(a)) adjusts a value, which needs a sliding gesture; this gesture fires once."))
                case (true, let action) where !isAdjust(action):
                    result.append(.init(kind: .discreteActionOnContinuousGesture, bindingIDs: [a.id],
                                        message: "\(label(a)) is a sliding gesture, so it can only adjust a value, not run this action."))
                default: break
                }
            }
            for b in bindings[(i + 1)...] where a.enabled && b.enabled && a.gesture == b.gesture
                && a.modifiers == b.modifiers && overlap(a, b) {
                result.append(.init(kind: .duplicateTrigger, bindingIDs: [a.id, b.id],
                                    message: "Two bindings use \(label(a)) in the same scope; only the first will run."))
            }
        }
        return result
    }

    private static func isAdjust(_ action: Action) -> Bool {
        if case .adjust = action { return true }
        return false
    }

    private static func overlap(_ a: Binding, _ b: Binding) -> Bool {
        (a.isGlobal && b.isGlobal) || !Set(a.apps).isDisjoint(with: b.apps)
    }

    private static func label(_ b: Binding) -> String {
        (["\(b.gesture.id)"] + Modifiers.named.filter { b.modifiers.contains($0.0) }.map(\.1)).joined(separator: " + ")
    }
}
