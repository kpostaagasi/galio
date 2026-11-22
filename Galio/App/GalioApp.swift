import SwiftUI

@main
struct GalioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = GameSession.shared
    @StateObject private var store = DataStore.shared
    @StateObject private var overlay = OverlayController.shared

    var body: some Scene {
        WindowGroup("Galio", id: "main") {
            ContentView()
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(overlay)
                .frame(minWidth: 780, minHeight: 540)
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Katmanı göster/gizle") { overlay.toggle() }
                    .keyboardShortcut("g", modifiers: [.option, .shift])
            }
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(session)
                .environmentObject(overlay)
        } label: {
            Image(systemName: "shield.lefthalf.filled")
                .accessibilityLabel("Galio")
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(overlay)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let store = DataStore.shared
            store.loadInitial()
            let session = GameSession.shared
            let overlay = OverlayController.shared
            overlay.setup()
            session.onPhaseChange = { _, new in
                OverlayController.shared.phaseChanged(to: new)
            }
            session.start()
            if MockLaunch.scenarioName != nil {
                overlay.show()
            }
            let autoRefresh = UserDefaults.standard.object(forKey: "dataAutoRefresh") as? Bool ?? true
            if autoRefresh && !ProcessInfo.processInfo.arguments.contains("--offline") {
                Task { await store.refresh() }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
