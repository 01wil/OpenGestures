// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI
import Windows

struct SwitcherCard: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let icon: NSImage?
    var thumbnail: NSImage?

    init(id: CGWindowID, title: String, appName: String, icon: NSImage?, thumbnail: NSImage? = nil) {
        (self.id, self.title, self.appName, self.icon, self.thumbnail) = (id, title, appName, icon, thumbnail)
    }

    init(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        self.init(id: window.id, title: window.title, appName: app?.localizedName ?? "", icon: app?.icon)
    }
}

@MainActor @Observable
final class SwitcherState {
    var cards: [SwitcherCard] = []
    var selected = 0
    var olderToTheLeft = true
}

/// The window switcher overlay: a borderless panel that never takes focus, above other windows on every
/// Space, centred on the screen with the pointer. Thumbnails appear only when Screen Recording is already
/// granted; it is never requested.
@MainActor
final class SwitcherPanel {
    private let state = SwitcherState()
    private var thumbnails: Task<Void, Never>?
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SwitcherView(state: state))
        return panel
    }()

    var window: NSWindow { panel }

    func show(_ cards: [SwitcherCard], selected: Int, olderToTheLeft: Bool) {
        state.cards = cards
        state.selected = selected
        state.olderToTheLeft = olderToTheLeft
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let size = panel.contentView?.fittingSize ?? .zero
        let width = min(size.width, area.width - 2 * Design.switcherRadius)
        panel.setFrame(CGRect(x: area.midX - width / 2, y: area.midY - size.height / 2, width: width, height: size.height), display: true)
        panel.orderFrontRegardless()
        loadThumbnails()
    }

    func select(_ index: Int) { state.selected = index }

    func hide() {
        thumbnails?.cancel()
        panel.orderOut(nil)
        state.cards = []
    }

    private func loadThumbnails() {
        thumbnails?.cancel()
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = state.cards.map(\.id)
        thumbnails = Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            for id in ids {
                guard !Task.isCancelled else { return }
                guard let window = content.windows.first(where: { $0.windowID == id }), window.frame.height > 0 else { continue }
                let config = SCStreamConfiguration()
                let scale = 2 * Design.switcherCard.height / window.frame.height
                config.width = Int(window.frame.width * scale)
                config.height = Int(window.frame.height * scale)
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: window)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                      !Task.isCancelled, let i = state.cards.firstIndex(where: { $0.id == id }) else { continue }
                state.cards[i].thumbnail = NSImage(cgImage: image, size: .zero)
            }
        }
    }
}

struct SwitcherView: View {
    let state: SwitcherState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let order = state.olderToTheLeft ? Array(state.cards.indices.reversed()) : Array(state.cards.indices)
        let visible = CGFloat(min(state.cards.count, Design.switcherVisibleCards))
        let cardWidth = Design.switcherCard.width + 2 * Design.spacing
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.spacing) {
                    ForEach(order, id: \.self) { i in
                        SwitcherCardView(card: state.cards[i], selected: i == state.selected)
                            .id(i)
                    }
                }
                .padding(Design.spacing * 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: visible * cardWidth + (visible - 1) * Design.spacing + 4 * Design.spacing)
            .onAppear { proxy.scrollTo(state.selected, anchor: .center) }
            .onChange(of: state.selected) { _, i in
                withAnimation(reduceMotion ? nil : Design.selectionMove) { proxy.scrollTo(i, anchor: .center) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.switcherRadius))
        .animation(reduceMotion ? nil : Design.selectionMove, value: state.selected)
    }
}

private struct SwitcherCardView: View {
    let card: SwitcherCard
    let selected: Bool

    var body: some View {
        VStack(spacing: Design.spacing) {
            Group {
                if let thumbnail = card.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Design.chipRadius))
                } else if let icon = card.icon {
                    Image(nsImage: icon).resizable().frame(width: Design.switcherIcon, height: Design.switcherIcon)
                }
            }
            .frame(width: Design.switcherCard.width, height: Design.switcherCard.height)
            HStack(spacing: Design.chipPadding) {
                if card.thumbnail != nil, let icon = card.icon {
                    Image(nsImage: icon).resizable().frame(width: Design.appIcon, height: Design.appIcon)
                }
                Text(card.title.isEmpty ? card.appName : card.title).lineLimit(1).truncationMode(.tail)
            }
            .frame(width: Design.switcherCard.width)
        }
        .padding(Design.spacing)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: Design.cardRadius))
        .overlay {
            if selected { RoundedRectangle(cornerRadius: Design.cardRadius).strokeBorder(Color.accentColor, lineWidth: Design.selectionLine) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
