import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var monitor: ClientMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(monitor.status.title)
        Divider()
        Button("Galio'yu aç") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
