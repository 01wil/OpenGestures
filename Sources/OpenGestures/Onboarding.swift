// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Config
import SwiftUI

struct OnboardingView: View {
    enum Step { case welcome, permission, conflict }

    @Environment(AppModel.self) private var model
    let done: () -> Void
    @ViewState private var index = 0

    init(done: @escaping () -> Void) { self.done = done }

    /// Clashes of the user's own gestures with macOS gestures that are switched on.
    private var conflicts: [String] { SystemGestureConflicts.findOnThisMac(model.config.bindings).map(\.message) }

    var body: some View {
        let conflicts = conflicts
        let steps: [Step] = [.welcome, .permission] + (conflicts.isEmpty ? [] : [.conflict])
        let index = min(index, steps.count - 1)
        let last = index == steps.count - 1
        VStack(spacing: Design.spacing) {
            Spacer()
            switch steps[index] {
            case .welcome: welcome
            case .permission: permission
            case .conflict: conflict(conflicts)
            }
            Spacer()
            HStack {
                if !last { Button("Skip", action: done) }
                Spacer()
                if index > 0 { Button("Back") { self.index = index - 1 } }
                Button(last ? "Done" : "Continue") { if last { done() } else { self.index = index + 1 } }
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
                GridRow {
                    Text("5 fingers ← →").bold()
                    Text("Left / right half of the screen")
                }
                GridRow {
                    Text("4 / 5 finger tap").bold()
                    Text("Maximize / center the window")
                }
                GridRow {
                    Text("TipTap ← →").bold()
                    Text("Previous / next track")
                }
                GridRow {
                    Text("Slide along an edge").bold()
                    Text("Volume (right), brightness (left)")
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
            AccessibilityStatus()
            if !model.accessibilityGranted {
                Button("Allow Access…", action: System.requestAccessibility)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func conflict(_ messages: [String]) -> some View {
        VStack(spacing: Design.spacing) {
            header("exclamationmark.triangle", "macOS Uses These Gestures Too")
            ForEach(messages, id: \.self) { Text($0) }
            Text("Both would happen. You can turn the macOS gesture off or change it in Trackpad settings.")
                .foregroundStyle(.secondary)
            Button("Open Trackpad Settings…") { NSWorkspace.shared.open(System.trackpadSettings) }
        }
        .multilineTextAlignment(.center)
    }
}
