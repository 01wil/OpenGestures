// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Model
import Testing
@testable import Windows

@Suite struct DisplayOrderTests {
    let frames = [
        CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1920, y: -1080, width: 1920, height: 1080),
    ]

    @Test func ordersLeftToRightThenByMinY() {
        #expect(DisplayGeometry.ordered(frames) == [1, 2, 0])
    }

    @Test func nextAndPreviousWrap() {
        #expect(DisplayGeometry.adjacent(to: 1, in: frames, forward: true) == 2)
        #expect(DisplayGeometry.adjacent(to: 0, in: frames, forward: true) == 1)
        #expect(DisplayGeometry.adjacent(to: 1, in: frames, forward: false) == 0)
        #expect(DisplayGeometry.adjacent(to: 2, in: frames, forward: false) == 1)
    }

    @Test func singleOrInvalidDisplayHasNoNeighbour() {
        #expect(DisplayGeometry.adjacent(to: 0, in: [frames[0]], forward: true) == nil)
        #expect(DisplayGeometry.adjacent(to: 5, in: frames, forward: true) == nil)
    }
}

@Suite struct MoveToDisplayTests {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    @Test func keepsSizeAndEdgeInsets() {
        let r = DisplayGeometry.rect(moving: CGRect(x: 100, y: 100, width: 800, height: 600),
                                     from: laptop, to: external)
        // left inset 100 kept; top inset (875 - 700 = 175) kept.
        #expect(r == CGRect(x: 1540, y: 280, width: 800, height: 600))
    }

    @Test func windowFillingSourceFillsTarget() {
        #expect(DisplayGeometry.rect(moving: laptop, from: laptop, to: external) == external)
        let almost = laptop.insetBy(dx: 4, dy: 4)
        #expect(DisplayGeometry.rect(moving: almost, from: laptop, to: external) == external)
    }

    @Test func shrinksToFitAndStaysInside() {
        let big = CGRect(x: 60, y: 40, width: 1800, height: 1000)
        let r = DisplayGeometry.rect(moving: big, from: external, to: laptop)
        #expect(r.size == CGSize(width: 1440, height: 875))
        #expect(laptop.contains(r))
    }

    @Test func rightAlignedWindowStaysRightAligned() {
        let w = CGRect(x: 1440 - 500, y: 0, width: 500, height: 400)
        let r = DisplayGeometry.rect(moving: w, from: laptop, to: external)
        #expect(r.maxX == external.maxX)
    }

    @Test func clampsIntoTargetWithNonZeroOrigin() {
        let target = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let r = DisplayGeometry.rect(moving: CGRect(x: 1000, y: 100, width: 800, height: 700),
                                     from: laptop, to: target)
        #expect(target.contains(r))
        #expect(r.size == CGSize(width: 800, height: 700))
    }

    @Test func degenerateFramesReturnWindowUnchanged() {
        let w = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(DisplayGeometry.rect(moving: w, from: .zero, to: external) == w)
    }
}

@Suite struct CoordinateTests {
    @Test func axToAppKitFlipsAroundPrimaryHeight() {
        let ax = CGRect(x: 100, y: 50, width: 800, height: 600)
        let ak = DisplayGeometry.appKit(fromAX: ax, primaryMaxY: 900)
        #expect(ak == CGRect(x: 100, y: 250, width: 800, height: 600))
        #expect(DisplayGeometry.ax(fromAppKit: ak, primaryMaxY: 900) == ax)
    }

    @Test func windowAbovePrimaryHasNegativeAXY() {
        let ak = CGRect(x: 0, y: 1000, width: 400, height: 300)
        #expect(DisplayGeometry.ax(fromAppKit: ak, primaryMaxY: 900).origin.y == -400)
    }
}

@Suite struct LayoutFrameTests {
    let size = CGSize(width: 800, height: 600)
    let visibles = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1440, y: -180, width: 1920, height: 1055),
    ]

    func f(_ l: WindowLayout, _ v: CGRect) -> CGRect { DisplayGeometry.frame(for: l, windowSize: size, in: v) }

    @Test func fixedFramesOn1440x900() {
        let v = visibles[0]
        #expect(f(.maximize, v) == v)
        #expect(f(.leftHalf, v) == CGRect(x: 0, y: 0, width: 720, height: 900))
        #expect(f(.rightHalf, v) == CGRect(x: 720, y: 0, width: 720, height: 900))
        #expect(f(.topHalf, v) == CGRect(x: 0, y: 450, width: 1440, height: 450))
        #expect(f(.bottomHalf, v) == CGRect(x: 0, y: 0, width: 1440, height: 450))
        #expect(f(.topLeft, v) == CGRect(x: 0, y: 450, width: 720, height: 450))
        #expect(f(.topRight, v) == CGRect(x: 720, y: 450, width: 720, height: 450))
        #expect(f(.bottomLeft, v) == CGRect(x: 0, y: 0, width: 720, height: 450))
        #expect(f(.bottomRight, v) == CGRect(x: 720, y: 0, width: 720, height: 450))
        #expect(f(.center, v) == CGRect(x: 320, y: 150, width: 800, height: 600))
    }

    @Test func fixedFramesOn1920x1080() {
        let v = visibles[1]
        #expect(f(.rightHalf, v) == CGRect(x: 960, y: 0, width: 960, height: 1080))
        #expect(f(.topRight, v) == CGRect(x: 960, y: 540, width: 960, height: 540))
        #expect(f(.center, v) == CGRect(x: 560, y: 240, width: 800, height: 600))
    }

    @Test func nonZeroOriginAndOddHeight() {
        let v = visibles[2]
        #expect(f(.leftHalf, v) == CGRect(x: 1440, y: -180, width: 960, height: 1055))
        #expect(f(.bottomHalf, v) == CGRect(x: 1440, y: -180, width: 1920, height: 527))
        #expect(f(.topHalf, v) == CGRect(x: 1440, y: 347, width: 1920, height: 528))
    }

    @Test func centerShrinksOversizedWindow() {
        let r = DisplayGeometry.frame(for: .center, windowSize: CGSize(width: 5000, height: 5000), in: visibles[0])
        #expect(r == visibles[0])
    }

    @Test func everyLayoutStaysInsideVisibleFrame() {
        for v in visibles {
            for l in WindowLayout.allCases {
                #expect(v.contains(f(l, v)), "\(l) in \(v)")
            }
        }
    }

    @Test func halvesTileWithoutOverlapOrGap() {
        for v in visibles {
            let l = f(.leftHalf, v), r = f(.rightHalf, v)
            #expect(l.maxX == r.minX && r.maxX == v.maxX)
            let b = f(.bottomHalf, v), t = f(.topHalf, v)
            #expect(b.maxY == t.minY && t.maxY == v.maxY)
        }
    }
}
