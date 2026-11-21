// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Vorssaint (https://github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later.
// Copyright (C) 2026 Vorssaint
//
// Vorssaint's Cmd-Tab switcher panel (Services/Switcher/AppSwitcher.swift: showPanel, centeredFrame, ensurePanel,
// SwitcherGrid; Services/Switcher/SwitcherSupport.swift: SwitcherGridCard, gridColumnCount; UI/Switcher/SwitcherView.swift:
// standardPanel, cardGrid, WindowCard; UI/SharedUI.swift: HUDBackdropMaterial) without its hotkeys, hover, close buttons,
// search and settings: the gesture opens it, steps the selection and commits on lift (see Engine).

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
    var preview: CGImage?

    init(id: CGWindowID, title: String, appName: String, icon: NSImage?, preview: CGImage? = nil) {
        (self.id, self.title, self.appName, self.icon, self.preview) = (id, title, appName, icon, preview)
    }

    init(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        self.init(id: window.id, title: window.title, appName: app?.localizedName ?? "", icon: app?.icon)
    }

    /// Label shown under the thumbnail; untitled windows fall back to the app name.
    var displayTitle: String { title.isEmpty ? appName : title }

    /// The app's name under the title, unless the title already is the app's name.
    var displaySubtitle: String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAppName.isEmpty, !cleanTitle.isEmpty, cleanTitle.caseInsensitiveCompare(cleanAppName) != .orderedSame else { return nil }
        return cleanAppName
    }
}

@MainActor @Observable
final class SwitcherState {
    var cards: [SwitcherCard] = []
    var selected = 0
    var grid = SwitcherGrid.empty
}

/// The window switcher overlay: a borderless panel that never takes focus, above other windows on every
/// Space, centred on the screen with the pointer. Thumbnails appear only when Screen Recording is already
/// granted; it is never requested. Without it each card shows the app's icon.
@MainActor
final class SwitcherPanel {
    private let state = SwitcherState()
    private var previews: Task<Void, Never>?
    private lazy var panel: NSPanel = {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingController(rootView: SwitcherView(state: state))
        // The panel's frame is set from the grid below; the hosting view must not resize it from a corner.
        host.sizingOptions = []
        panel.contentViewController = host
        return panel
    }()

    var window: NSWindow { panel }

    func show(_ cards: [SwitcherCard], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        state.cards = cards
        state.selected = selected
        state.grid = SwitcherGrid.compute(count: cards.count, visibleFrame: area)
        let size = state.grid.panelSize
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        let animationBehavior = panel.animationBehavior
        panel.animationBehavior = .none
        panel.orderFrontRegardless()
        panel.animationBehavior = animationBehavior
        loadPreviews()
    }

    func select(_ index: Int) { state.selected = index }

    func hide() {
        previews?.cancel()
        panel.orderOut(nil)
        state.cards = []
    }

    private func loadPreviews() {
        previews?.cancel()
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = state.cards.map(\.id)
        let maxPixelSize = 2 * SwitcherGridCard.thumbnailWidth
        previews = Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            for id in ids {
                guard !Task.isCancelled else { return }
                guard let window = content.windows.first(where: { $0.windowID == id }), window.frame.width > 1, window.frame.height > 1 else { continue }
                let config = SCStreamConfiguration()
                let scale = min(1, maxPixelSize / max(window.frame.width, window.frame.height))
                config.width = max(1, Int((window.frame.width * scale).rounded()))
                config.height = max(1, Int((window.frame.height * scale).rounded()))
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: window)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                      !Task.isCancelled, let i = state.cards.firstIndex(where: { $0.id == id }) else { continue }
                state.cards[i].preview = image
            }
        }
    }
}

/// Keeps VoiceOver from announcing the overlay as a window.
private final class OverlayPanel: NSPanel {
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

enum SwitcherGridCard {
    static let width: CGFloat = 288
    static let height: CGFloat = 214
    static let padding: CGFloat = 10
    static let titleSpacing: CGFloat = 7
    /// One 13pt line over one 10.5pt line, 2pt apart, descenders included.
    static let titleHeight: CGFloat = 31
    static var thumbnailWidth: CGFloat { width - padding * 2 }
    static var thumbnailHeight: CGFloat { height - padding * 2 - titleSpacing - titleHeight }
    /// The title band sits inside the thumbnail's width so a long name stops short of the card's rounded corners.
    static var titleWidth: CGFloat { thumbnailWidth - 8 }
    static let fallbackIconSize: CGFloat = 80
}

/// Grid metrics for one switcher session: large cards laid out in as many rows as needed, sized to the
/// screen the panel opens on.
struct SwitcherGrid: Equatable {
    let columns: Int
    let rows: Int
    let visibleRows: Int
    let panelSize: CGSize

    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20
    static let empty = SwitcherGrid(columns: 1, rows: 1, visibleRows: 1, panelSize: .zero)

    static func compute(count: Int, visibleFrame: CGRect) -> SwitcherGrid {
        let cardWidth = SwitcherGridCard.width, cardHeight = SwitcherGridCard.height
        let usableWidth = visibleFrame.width * 0.92
        let usableHeight = visibleFrame.height * 0.85
        let fitByWidth = max(1, Int((usableWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        // As many columns as fit, then balanced so the last row is not left nearly empty.
        let items = max(count, 1)
        let packed = min(items, fitByWidth)
        let packedRows = (items + packed - 1) / packed
        let columns = min(packed, (items + packedRows - 1) / packedRows)
        let rows = (items + columns - 1) / columns
        let maxRows = max(1, Int((usableHeight - padding * 2 + spacing) / (cardHeight + spacing)))
        let visibleRows = min(rows, maxRows)
        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * spacing + padding * 2
        return SwitcherGrid(columns: columns, rows: rows, visibleRows: visibleRows, panelSize: CGSize(width: width, height: height))
    }
}

/// Content of the switcher panel: a grid of large window cards with live thumbnails and a springy highlight.
struct SwitcherView: View {
    let state: SwitcherState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        cardGrid
            .padding(SwitcherGrid.padding)
            .frame(width: state.grid.panelSize.width, height: state.grid.panelSize.height)
            .background(HUDBackdropMaterial(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var cardGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(SwitcherGridCard.width), spacing: SwitcherGrid.spacing), count: state.grid.columns),
                          spacing: SwitcherGrid.spacing) {
                    ForEach(Array(state.cards.enumerated()), id: \.element.id) { index, card in
                        WindowCard(card: card, isSelected: index == state.selected, animatesSelection: !reduceMotion)
                            .id(card.id)
                    }
                }
            }
            .scrollDisabled(state.grid.rows <= state.grid.visibleRows)
            .onAppear {
                guard state.cards.indices.contains(state.selected) else { return }
                proxy.scrollTo(state.cards[state.selected].id, anchor: nil)
            }
            .onChange(of: state.selected) { _, newIndex in
                guard state.cards.indices.contains(newIndex) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(state.cards[newIndex].id, anchor: nil) }
            }
        }
    }
}

private struct WindowCard: View {
    let card: SwitcherCard
    let isSelected: Bool
    let animatesSelection: Bool

    private static let appBadgeSize: CGFloat = 32
    /// App artwork is drawn on the system icon grid, which leaves a clear margin around it (about 9.4% of the
    /// side). The badge hangs past the row by that much so the artwork itself lines up with the card edge.
    private static let appBadgeArtworkInset: CGFloat = (appBadgeSize * 0.094).rounded()

    var body: some View {
        VStack(spacing: SwitcherGridCard.titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                if let preview = card.preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(5)
                } else if let icon = card.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: SwitcherGridCard.fallbackIconSize, height: SwitcherGridCard.fallbackIconSize)
                }

                // Without a thumbnail the app icon already fills the card, so the corner badge would only repeat it.
                if card.preview != nil, let icon = card.icon {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 8) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: Self.appBadgeSize, height: Self.appBadgeSize)
                                .shadow(radius: 3)
                                .padding(.leading, -Self.appBadgeArtworkInset)
                                .padding(.bottom, -Self.appBadgeArtworkInset)
                            Spacer(minLength: 0)
                        }
                        .padding(7)
                    }
                }
            }
            .frame(width: SwitcherGridCard.thumbnailWidth, height: SwitcherGridCard.thumbnailHeight)

            VStack(spacing: 2) {
                Text(card.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if let subtitle = card.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: SwitcherGridCard.titleHeight, alignment: .top)
            .frame(maxWidth: SwitcherGridCard.titleWidth)
        }
        .padding(SwitcherGridCard.padding)
        .frame(width: SwitcherGridCard.width, height: SwitcherGridCard.height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Color.white.opacity(0.14) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(animatesSelection ? .spring(response: 0.25, dampingFraction: 0.8) : nil, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.displaySubtitle.map { "\(card.displayTitle), \($0)" } ?? card.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The HUD material behind the panel (it turns solid by itself under Reduce Transparency). Rounding the effect
/// view's own layer matters: SwiftUI's `.clipShape` does not clip an `NSVisualEffectView`'s
/// behind-window material, which otherwise shows as a faint rectangle just outside the rounded panel.
private struct HUDBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
