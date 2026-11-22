import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var overlay: OverlayController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(session.connection.isConnected ? session.phase.title : Loc.tr("League istemcisi kapalı"))
        if let mode = session.mode {
            Text(mode.title)
        }
        Divider()
        Button("Galio'yu aç") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button(overlay.isVisible ? Loc.tr("Katmanı gizle") : Loc.tr("Katmanı göster")) {
            overlay.toggle()
        }
        SettingsLink {
            Text("Ayarlar…")
        }
        Divider()
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
