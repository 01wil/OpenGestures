// SPDX-License-Identifier: GPL-3.0-or-later

import CMultitouch
import Testing
@testable import MultitouchBridge

@Suite struct ConversionTests {
    private func touch(id: Int32 = 1, x: Float = 0.5, y: Float = 0.5, size: Float = 1) -> MTTouch {
        var t = MTTouch()
        t.identifier = id
        t.normalized.position = MTPoint(x: x, y: y)
        t.size = size
        return t
    }

    @Test func convertsFiniteTouches() {
        let raw = [touch(id: 3, x: 0.25, y: 0.75)]
        let list = raw.withUnsafeBufferPointer { MultitouchBridge.touches(from: $0.baseAddress, count: 1) }
        #expect(list.count == 1)
        #expect(list[0].id == 3 && list[0].x == 0.25 && list[0].y == 0.75)
    }

    @Test(arguments: [Int32(-1), .min, 0])
    func nonPositiveCountYieldsNothing(count: Int32) {
        let raw = [touch()]
        #expect(raw.withUnsafeBufferPointer { MultitouchBridge.touches(from: $0.baseAddress, count: count) }.isEmpty)
    }

    @Test func nilPointerYieldsNothing() {
        #expect(MultitouchBridge.touches(from: nil, count: 5).isEmpty)
    }

    @Test func hugeCountIsClamped() {
        let raw = Array(repeating: touch(), count: 100)
        let list = raw.withUnsafeBufferPointer { MultitouchBridge.touches(from: $0.baseAddress, count: 100) }
        #expect(list.count == MultitouchBridge.maxTouches)
    }

    @Test func nonFiniteTouchesAreSkipped() {
        let raw = [touch(id: 1, x: .nan), touch(id: 2, y: .infinity), touch(id: 3, size: -.infinity), touch(id: 4)]
        let list = raw.withUnsafeBufferPointer { MultitouchBridge.touches(from: $0.baseAddress, count: 4) }
        #expect(list.map(\.id) == [4])
    }
}
