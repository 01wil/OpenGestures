// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Config
import SwiftUI

struct OnboardingView: View {
    enum Step { case welcome, permission, conflict }

    let done: () -> Void
    private let steps: [Step]
    @ViewState private var index = 0
    @ViewState private var granted = System.accessibilityGranted

    init(done: @escaping () -> Void) {
        self.done = done
        let clash = !SystemGestureConflicts.findOnThisMac(Configuration.default.bindings).isEmpty
        steps = [.welcome, .permission] + (clash ? [.conflict] : [])
    }

    var body: some View {
        let last = index == steps.count - 1
        VStack(spacing: Design.spacing) {
            Spacer()
            switch steps[index] {
            case .welcome: welcome
            case .permission: permission
            case .conflict: conflict
            }
            Spacer()
            HStack {
                if !last { Button("Skip", action: done) }
                Spacer()
                if index > 0 { Button("Back") { index -= 1 } }
                Button(last ? "Done" : "Continue") { if last { done() } else { index += 1 } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: Design.onboardingSize.width, height: Design.onboardingSize.height)
    }

    private func header(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: Design.spacing) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint)
            Text(title).font(.title2).bold()
        }
    }

    private var welcome: some View {
        VStack(spacing: Design.spacing) {
            header("hand.draw", "Welcome to OpenGestures")
            Text("Trackpad gestures for your own actions. These work right away:")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: Design.spacing * 2, verticalSpacing: Design.spacing) {
                GridRow {
                    Text("4 fingers ← →").bold()
                    Text("Previous / next window")
                }
                GridRow {
                    Text("⌘ + 4 fingers ← →").bold()
                    Text("Move window to the other display")
                }
            }
            .padding(.top, Design.spacing)
        }
        .multilineTextAlignment(.center)
    }

    private var permission: some View {
        VStack(spacing: Design.spacing) {
            header("lock", "Allow Accessibility")
            Text("OpenGestures needs Accessibility access to switch and move windows and to send keys.")
                .foregroundStyle(.secondary)
            AccessibilityStatus(granted: $granted)
            Button("Open System Settings…", action: System.requestAccessibility)
        }
        .multilineTextAlignment(.center)
    }

    private var conflict: some View {
        VStack(spacing: Design.spacing) {
            header("exclamationmark.triangle", "macOS Uses This Swipe Too")
            Text("Your Mac switches desktops with a 4-finger swipe, so both would happen. You can turn it off or change it to 3 fingers in Trackpad settings.")
                .foregroundStyle(.secondary)
            Button("Open Trackpad Settings…") { NSWorkspace.shared.open(System.trackpadSettings) }
        }
        .multilineTextAlignment(.center)
    }
}
