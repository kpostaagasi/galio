import AppKit
import SwiftUI

/// Floating, non-activating panel that sits above the (borderless/windowed) game.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 80, y: 400, width: 340, height: 220),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        title = "Galio Overlay"
        setAccessibilityLabel("Galio overlay")
    }

    // Allows the manual augment search field to receive typing without activating the app.
    override var canBecomeKey: Bool { true }

    /// The SwiftUI content drives the panel size (collapsed/expanded, phase). Keep the top-left
    /// corner where the user put it when only the size changes, and keep the panel on screen.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        let old = frame
        if old.width > 0, old.height > 0, r.origin == old.origin, r.size != old.size {
            r.origin.y = old.maxY - r.height
        }
        if let visible = (screen ?? NSScreen.main)?.visibleFrame, r.width <= visible.width, r.height <= visible.height {
            r.origin.x = min(max(r.origin.x, visible.minX), visible.maxX - r.width)
            r.origin.y = min(max(r.origin.y, visible.minY), visible.maxY - r.height)
        }
        super.setFrame(r, display: flag)
    }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    @Published private(set) var isVisible = false
    private var panel: OverlayPanel?
    private var hotKey: HotKey?

    static let frameName = "GalioOverlayPanel.v2"
    static let opacityKey = "overlayOpacity"
    static let clickThroughKey = "overlayClickThrough"
    static let autoShowKey = "overlayAutoShow"
    static let hotKeyEnabledKey = "overlayHotKeyEnabled"
    static let expandedKey = "overlayExpanded"
    static let compactWidth: CGFloat = 288
    static let expandedWidth: CGFloat = 350

    func setup() {
        guard panel == nil else { return }
        UserDefaults.standard.register(defaults: [
            Self.opacityKey: 0.92,
            Self.clickThroughKey: false,
            Self.autoShowKey: true,
            Self.hotKeyEnabledKey: true,
            Self.expandedKey: false,
        ])
        let panel = OverlayPanel()
        let root = OverlayView()
            .environmentObject(GameSession.shared)
            .environmentObject(DataStore.shared)
            .environmentObject(self)
            .environmentObject(ActionCenter.shared)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        // Position is remembered (frame autosave); the size follows the collapsed/expanded state,
        // which is remembered too. Default: top-right corner, away from the main window's content.
        if !panel.setFrameUsingName(Self.frameName), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.maxX - Self.compactWidth - 16, y: f.maxY - 12))
        }
        panel.setFrameAutosaveName(Self.frameName)
        self.panel = panel
        applySettings()
        updateHotKey()
    }

    func applySettings() {
        let d = UserDefaults.standard
        panel?.alphaValue = CGFloat(min(1, max(0.3, d.double(forKey: Self.opacityKey))))
        panel?.ignoresMouseEvents = d.bool(forKey: Self.clickThroughKey)
    }

    func updateHotKey() {
        if UserDefaults.standard.bool(forKey: Self.hotKeyEnabledKey) {
            if hotKey == nil {
                hotKey = HotKey { [weak self] in
                    Task { @MainActor in self?.toggle() }
                }
            }
        } else {
            hotKey = nil
        }
    }

    func show() {
        setup()
        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() { isVisible ? hide() : show() }

    func setClickThrough(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.clickThroughKey)
        applySettings()
    }

    /// Auto show/hide with the game flow when enabled in Settings.
    func phaseChanged(to phase: GameflowPhase) {
        guard MockLaunch.section == nil else { return }
        if Self.hidesOverlay(phase) {
            hide()
        } else if Self.wantsOverlay(phase) && UserDefaults.standard.bool(forKey: Self.autoShowKey) {
            show()
        }
    }

    /// Phases in which the overlay appears automatically.
    nonisolated static func wantsOverlay(_ phase: GameflowPhase) -> Bool {
        [.champSelect, .inProgress, .gameStart, .reconnect].contains(phase)
    }

    /// Phases in which it is hidden automatically: out of game, post-game (details live in the
    /// main window) and when the client is closed (phase `.none`).
    nonisolated static func hidesOverlay(_ phase: GameflowPhase) -> Bool {
        [.none, .lobby, .matchmaking, .readyCheck, .waitingForStats, .preEndOfGame, .endOfGame, .terminatedInError].contains(phase)
    }
}
