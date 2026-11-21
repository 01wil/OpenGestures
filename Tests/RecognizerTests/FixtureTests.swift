// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model
import Testing
@testable import Recognizer

/// Recorded fixtures from og-record: `Fixtures/<gesture-id>__<anything>.json` must yield that gesture exactly once
/// (every event, for a continuous gesture); `none__<anything>.json` must yield nothing.
enum Fixture {
    enum Expectation: Equatable {
        case none
        case gesture(Gesture)
    }

    static var urls: [URL] {
        (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func load(_ url: URL) throws -> [TouchFrame] {
        try JSONDecoder().decode([TouchFrame].self, from: Data(contentsOf: url))
    }

    static func expectation(forFileNamed name: String) -> Expectation? {
        guard let range = name.range(of: "__") else { return nil }
        let id = String(name[..<range.lowerBound])
        if id == "none" { return Expectation.none }
        return Gesture(id: id).map(Expectation.gesture)
    }

    static func check(_ events: [GestureEvent], against expectation: Expectation) -> Bool {
        switch expectation {
        case .none: events.isEmpty
        case let .gesture(g) where g.isContinuous: !events.isEmpty && events.allSatisfy { $0.gesture == g }
        case let .gesture(g): events == [GestureEvent(g)]
        }
    }

    /// How far the finger moved along `edge`, from its first to its last touching frame.
    static func slideTravel(_ frames: [TouchFrame], edge: Gesture.Edge) -> Double {
        let points = frames.compactMap { $0.touches.first { $0.isTouching } }
        guard let first = points.first, let last = points.last else { return 0 }
        switch edge {
        case .left, .right: return Double(last.y - first.y)
        case .top, .bottom: return Double(last.x - first.x)
        }
    }
}

@Suite struct FixtureTests {
    static let names = Fixture.urls.map { $0.deletingPathExtension().lastPathComponent }

    /// 0.5 is the Tuning default, 0.65 the sensitivity the app ships with.
    static let sensitivities = [0.5, 0.65]

    @Test(arguments: names, sensitivities) func recordedFixtureYieldsItsGesture(_ name: String, sensitivity: Double) throws {
        let expected = try #require(Fixture.expectation(forFileNamed: name),
                                    "name must be <gesture-id>__<anything> or none__<anything>")
        let url = try #require(Fixture.urls.first { $0.deletingPathExtension().lastPathComponent == name })
        let frames = try Fixture.load(url)
        let events = recognize(frames, tuning: Tuning(sensitivity: sensitivity))
        #expect(Fixture.check(events, against: expected), "expected \(expected), got \(events.map(\.gesture.id))")

        // A continuous gesture must also move the right way by about the right amount: the deltas add up to the
        // finger's travel along the edge, so an inverted sign or a wrong scale fails here.
        guard case let .gesture(g) = expected, case let .edgeSlide(edge) = g else { return }
        let travel = Fixture.slideTravel(frames, edge: edge)
        let total = events.compactMap(\.delta).reduce(0, +)
        #expect(abs(travel) > 0.1, "fixture should be a real slide, travel \(travel)")
        #expect(total.sign == travel.sign, "slide went \(travel) but events sum to \(total)")
        #expect(abs(total - travel) < 0.1 * abs(travel), "events sum to \(total), finger travelled \(travel)")
    }

    /// Every gesture the guided recorder asks for, read from its source so the two cannot drift apart.
    @Test func everyGuidedGestureHasAFixture() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/og-record/main.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let guided = Set(text.matches(of: /\("([a-z0-9.]+)", "/).map { String($0.1) })
        #expect(guided.count > 20)
        let recorded = Set(Self.names.map { String($0.prefix { $0 != "_" }) })
        #expect(guided.subtracting(recorded).isEmpty, "no fixture for \(guided.subtracting(recorded).sorted())")
    }

    @Test func parsesFixtureNames() {
        #expect(Fixture.expectation(forFileNamed: "swipe.4.left__laptop-1") == .gesture(.swipe(fingers: 4, direction: .left)))
        #expect(Fixture.expectation(forFileNamed: "none__palm-rest") == Fixture.Expectation.none)
        #expect(Fixture.expectation(forFileNamed: "swipe.4.left") == nil)
        #expect(Fixture.expectation(forFileNamed: "bogus__x") == nil)
    }

    @Test func loadsFramesInTheRecorderFormat() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("og-fixture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Synth.swipe(fingers: 3, direction: .right)).write(to: url)
        let events = recognize(try Fixture.load(url))
        #expect(Fixture.check(events, against: .gesture(.swipe(fingers: 3, direction: .right))))
    }

    @Test func continuousFixturesMayFireRepeatedly() {
        let slide = GestureEvent(.edgeSlide(edge: .left), delta: 0.1)
        #expect(Fixture.check([slide, slide], against: .gesture(.edgeSlide(edge: .left))))
        #expect(!Fixture.check([slide, GestureEvent(.tap(fingers: 1))], against: .gesture(.edgeSlide(edge: .left))))
        #expect(!Fixture.check([], against: .gesture(.edgeSlide(edge: .left))))
    }
}
