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
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    @Published private(set) var isVisible = false
    private var panel: OverlayPanel?
    private var hotKey: HotKey?

    static let opacityKey = "overlayOpacity"
    static let clickThroughKey = "overlayClickThrough"
    static let autoShowKey = "overlayAutoShow"
    static let hotKeyEnabledKey = "overlayHotKeyEnabled"

    func setup() {
        guard panel == nil else { return }
        UserDefaults.standard.register(defaults: [
            Self.opacityKey: 0.92,
            Self.clickThroughKey: false,
            Self.autoShowKey: true,
            Self.hotKeyEnabledKey: true,
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
        panel.setFrameAutosaveName("GalioOverlayPanel")
        if !panel.setFrameUsingName("GalioOverlayPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.minX + 40, y: f.maxY - 60))
        }
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
        guard UserDefaults.standard.bool(forKey: Self.autoShowKey) else { return }
        switch phase {
        case .champSelect, .inProgress, .gameStart:
            show()
        case .none, .lobby, .matchmaking:
            hide()
        default:
            break
        }
    }
}
