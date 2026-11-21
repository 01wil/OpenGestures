// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Testing
@testable import Windows

@Suite struct RestoreMemoryTests {
    let original = CGRect(x: 100, y: 120, width: 800, height: 500)
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let half = CGRect(x: 0, y: 25, width: 720, height: 875)

    @Test func firstApplyAppliesAndRemembersTheOriginal() {
        var m = RestoreMemory<Int>()
        let r0 = m.toggle(1, current: original, target: screen)
        #expect(r0 == .apply)
        #expect(m.original(of: 1) == original)
    }

    @Test func applyingAgainRestoresAndForgets() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        let r1 = m.toggle(1, current: screen, target: screen)
        #expect(r1 == .restore(original))
        #expect(m.original(of: 1) == nil)
        let r2 = m.toggle(1, current: screen, target: screen)
        #expect(r2 == .apply)
    }

    @Test func atTargetWithinToleranceStillRestores() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        let off = screen.offsetBy(dx: 3, dy: -3).insetBy(dx: 1, dy: 1)
        let r3 = m.toggle(1, current: off, target: screen)
        #expect(r3 == .restore(original))
    }

    @Test func beyondToleranceAppliesInsteadAndKeepsTheFirstOriginal() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        let r4 = m.toggle(1, current: screen, target: half)
        #expect(r4 == .apply)
        #expect(m.original(of: 1) == original)
        let r5 = m.toggle(1, current: half, target: half)
        #expect(r5 == .restore(original))
    }

    @Test func alreadyAtTargetWithNothingSavedSavesNothing() {
        var m = RestoreMemory<Int>()
        let r6 = m.toggle(1, current: screen, target: screen)
        #expect(r6 == .apply)
        #expect(m.original(of: 1) == nil)
    }

    @Test func windowsAreIndependent() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        let r7 = m.toggle(2, current: screen, target: screen)
        #expect(r7 == .apply)
        #expect(m.original(of: 1) == original)
    }

    @Test func userResizeForgetsButOurOwnSizeDoesNot() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        m.placed(1, at: screen)
        let r8 = m.userResized(1, to: screen.size)
        #expect(!r8)
        let r9 = m.userResized(1, to: CGSize(width: 1441, height: 874))
        #expect(!r9)
        #expect(m.original(of: 1) == original)
        let r10 = m.userResized(1, to: CGSize(width: 1000, height: 875))
        #expect(r10)
        #expect(m.original(of: 1) == nil)
        let r11 = m.userResized(1, to: .zero)
        #expect(!r11)
    }

    @Test func placedRecordsTheSizeTheSystemActuallyGave() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        m.placed(1, at: CGRect(x: 0, y: 25, width: 1200, height: 875))
        let r12 = m.userResized(1, to: CGSize(width: 1200, height: 875))
        #expect(!r12)
    }

    @Test func forgetDropsTheEntry() {
        var m = RestoreMemory<Int>()
        _ = m.toggle(1, current: original, target: screen)
        m.forget(1)
        #expect(m.original(of: 1) == nil)
    }

    @Test func keepsAtMostCapacityWindowsAndEvictsTheOldest() {
        var m = RestoreMemory<Int>()
        let n = RestoreMemory<Int>.capacity
        for k in 0..<n { _ = m.toggle(k, current: original, target: screen) }
        _ = m.toggle(0, current: screen, target: half)  // updating an entry neither evicts nor refreshes it
        #expect((0..<n).allSatisfy { m.original(of: $0) == original })
        _ = m.toggle(n, current: original, target: screen)
        #expect(m.original(of: 0) == nil)
        #expect((1...n).allSatisfy { m.original(of: $0) == original })
    }

    @Test func snappedWindowRestoresOnSecondTap() {
        var m = RestoreMemory<Int>()
        let snapped = CGRect(x: 0, y: 25, width: 700, height: 860)
        _ = m.toggle(1, current: original, target: half)
        m.placed(1, at: snapped)
        let r = m.toggle(1, current: snapped, target: half)
        #expect(r == .restore(original))
        #expect(m.original(of: 1) == nil)
    }

    @Test func atPlacedFrameButOtherLayoutRequestedApplies() {
        var m = RestoreMemory<Int>()
        let snapped = CGRect(x: 0, y: 25, width: 700, height: 860)
        _ = m.toggle(1, current: original, target: half)
        m.placed(1, at: snapped)
        let r = m.toggle(1, current: snapped, target: screen)
        #expect(r == .apply)
        #expect(m.original(of: 1) == original)
    }

    @Test func reapplyingDoesNotOverwritePlaced() {
        var m = RestoreMemory<Int>()
        let snapped = CGRect(x: 0, y: 25, width: 700, height: 860)
        _ = m.toggle(1, current: original, target: half)
        m.placed(1, at: snapped)
        _ = m.toggle(1, current: CGRect(x: 300, y: 300, width: 400, height: 300), target: half)
        let r = m.toggle(1, current: snapped, target: half)
        #expect(r == .restore(original))
    }
}

@Suite struct DragRestoreFrameTests {
    // AX space: origin top-left, y grows downward.
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let size = CGSize(width: 800, height: 500)

    @Test func cursorKeepsItsRelativeXOnTheTitleBar() {
        let r = DisplayGeometry.restoredFrame(dragging: maximized.offsetBy(dx: 80, dy: 20), restoreSize: size,
                                              pointer: CGPoint(x: 800, y: 60), in: visible)
        // ratio = (800 - 80) / 1440 = 0.5, depth = 60 - 45 = 15
        #expect(r == CGRect(x: 400, y: 45, width: 800, height: 500))
    }

    @Test func clampsInsideTheVisibleFrame() {
        let left = DisplayGeometry.restoredFrame(dragging: maximized, restoreSize: size,
                                                 pointer: CGPoint(x: 0, y: 40), in: visible)
        #expect(left.minX == 0)
        let right = DisplayGeometry.restoredFrame(dragging: maximized, restoreSize: size,
                                                  pointer: CGPoint(x: 1440, y: 40), in: visible)
        #expect(right.maxX == 1440)
    }

    @Test func neverRisesAboveTheVisibleTop() {
        let r = DisplayGeometry.restoredFrame(dragging: maximized, restoreSize: size,
                                              pointer: CGPoint(x: 700, y: 5), in: visible)
        #expect(r.minY == 25)
    }

    @Test func grabDeeperThanTheRestoredHeightStaysOnTheWindow() {
        let r = DisplayGeometry.restoredFrame(dragging: maximized, restoreSize: CGSize(width: 800, height: 20),
                                              pointer: CGPoint(x: 700, y: 400), in: visible)
        #expect(r.minY >= 380)
    }

    @Test func windowWiderThanTheDisplayPinsToItsLeftEdge() {
        let r = DisplayGeometry.restoredFrame(dragging: maximized, restoreSize: CGSize(width: 2000, height: 500),
                                              pointer: CGPoint(x: 700, y: 40), in: visible)
        #expect(r.minX == 0)
    }
}
