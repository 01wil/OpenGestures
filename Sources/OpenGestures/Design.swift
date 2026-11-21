// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Every spacing, size and duration the views use.
enum Design {
    static let spacing: CGFloat = 8
    static let paneWidth: CGFloat = 520
    static let gesturesPaneHeight: CGFloat = 440
    static let glyphWidth: CGFloat = 20
    static let chipPadding: CGFloat = 4
    static let chipRadius: CGFloat = 4
    static let scriptHeight: CGFloat = 80
    static let editorHeight: CGFloat = 560
    static let appIcon: CGFloat = 16
    static let aboutIcon: CGFloat = 64
    static let onboardingSize = CGSize(width: 460, height: 340)
    static let stateChange = Animation.easeInOut(duration: 0.2)
    // Window switcher overlay.
    static let switcherCard = CGSize(width: 168, height: 105)
    static let switcherIcon: CGFloat = 64
    static let switcherVisibleCards = 8
    static let switcherRadius: CGFloat = 18
    static let cardRadius: CGFloat = 10
    static let selectionLine: CGFloat = 2
    static let selectionMove = Animation.easeOut(duration: 0.15)
}

/// The macOS 27 SDK declares `@State` as a macro whose plugin ships only with Xcode; the property wrapper
/// type is unchanged, so reaching it through an alias builds with the Command Line Tools.
typealias ViewState = SwiftUI.State
