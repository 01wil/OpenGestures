// SPDX-License-Identifier: GPL-3.0-or-later

import Config
import Model

public enum GestureKind: String, CaseIterable, Sendable {
    case swipe, tap, pinch, rotate, tipTap, edgeSwipe, cornerTap, edgeSlide

    public var title: String {
        switch self {
        case .swipe: "Swipe"
        case .tap: "Tap"
        case .pinch: "Pinch"
        case .rotate: "Rotate"
        case .tipTap: "TipTap"
        case .edgeSwipe: "Swipe from edge"
        case .cornerTap: "Corner tap"
        case .edgeSlide: "Slide along edge"
        }
    }

    public var fingers: ClosedRange<Int>? {
        switch self {
        case .swipe: Gesture.swipeFingers
        case .tap: Gesture.tapFingers
        case .pinch: Gesture.pinchFingers
        default: nil
        }
    }
}

/// Editor state for picking a gesture: every parameter keeps its value while the kind changes.
public struct GestureDraft: Equatable, Sendable {
    public var kind: GestureKind = .swipe
    public var fingers = 4
    public var direction: Gesture.Direction = .left
    public var pinch: Gesture.PinchDirection = .pinchIn
    public var rotation: Gesture.Rotation = .clockwise
    public var side: Gesture.Side = .left
    public var edge: Gesture.Edge = .left
    public var corner: Gesture.Corner = .topLeft

    public init(_ gesture: Gesture) {
        switch gesture {
        case let .swipe(n, d): (kind, fingers, direction) = (.swipe, n, d)
        case let .tap(n): (kind, fingers) = (.tap, n)
        case let .pinch(n, d): (kind, fingers, pinch) = (.pinch, n, d)
        case let .rotate(r): (kind, rotation) = (.rotate, r)
        case let .tipTap(s): (kind, side) = (.tipTap, s)
        case let .edgeSwipe(e): (kind, edge) = (.edgeSwipe, e)
        case let .cornerTap(c): (kind, corner) = (.cornerTap, c)
        case let .edgeSlide(e): (kind, edge) = (.edgeSlide, e)
        }
    }

    public var gesture: Gesture {
        let n = kind.fingers.map { min(max(fingers, $0.lowerBound), $0.upperBound) } ?? fingers
        return switch kind {
        case .swipe: .swipe(fingers: n, direction: direction)
        case .tap: .tap(fingers: n)
        case .pinch: .pinch(fingers: n, direction: pinch)
        case .rotate: .rotate(rotation)
        case .tipTap: .tipTap(side: side)
        case .edgeSwipe: .edgeSwipe(edge: edge)
        case .cornerTap: .cornerTap(corner: corner)
        case .edgeSlide: .edgeSlide(edge: edge)
        }
    }

    public static let allGestures: [Gesture] =
        Gesture.swipeFingers.flatMap { n in Gesture.Direction.allCases.map { Gesture.swipe(fingers: n, direction: $0) } }
        + Gesture.tapFingers.map { Gesture.tap(fingers: $0) }
        + Gesture.pinchFingers.flatMap { n in Gesture.PinchDirection.allCases.map { Gesture.pinch(fingers: n, direction: $0) } }
        + Gesture.Rotation.allCases.map { Gesture.rotate($0) }
        + Gesture.Side.allCases.map { Gesture.tipTap(side: $0) }
        + Gesture.Edge.allCases.map { Gesture.edgeSwipe(edge: $0) }
        + Gesture.Corner.allCases.map { Gesture.cornerTap(corner: $0) }
        + Gesture.Edge.allCases.map { Gesture.edgeSlide(edge: $0) }
}

extension Configuration {
    public mutating func upsert(_ binding: Binding) {
        if let i = bindings.firstIndex(where: { $0.id == binding.id }) { bindings[i] = binding } else { bindings.append(binding) }
    }

    public mutating func remove(id: Binding.ID) {
        bindings.removeAll { $0.id == id }
    }

    public mutating func setEnabled(_ enabled: Bool, id: Binding.ID) {
        if let i = bindings.firstIndex(where: { $0.id == id }) { bindings[i].enabled = enabled }
    }
}

/// Bindings sharing one scope: global (no apps) first, then each distinct app set in order of first appearance.
public struct BindingGroup: Identifiable, Equatable, Sendable {
    /// Sorted bundle identifiers; empty for global.
    public var apps: [String]
    public var bindings: [Binding]

    public var id: String { apps.joined(separator: ",") }

    public static func groups(_ bindings: [Binding]) -> [BindingGroup] {
        var result: [BindingGroup] = []
        for b in bindings {
            let key = b.apps.sorted()
            if let i = result.firstIndex(where: { $0.apps == key }) { result[i].bindings.append(b) }
            else { result.append(BindingGroup(apps: key, bindings: [b])) }
        }
        return result.filter(\.apps.isEmpty) + result.filter { !$0.apps.isEmpty }
    }
}
