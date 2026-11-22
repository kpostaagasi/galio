import SwiftUI

@main
struct GalioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = GameSession.shared
    @StateObject private var store = DataStore.shared
    @StateObject private var overlay = OverlayController.shared
    @StateObject private var actions = ActionCenter.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup("Galio", id: "main") {
            ContentView()
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(overlay)
                .environmentObject(actions)
                .environmentObject(history)
                .frame(minWidth: 860, minHeight: 580)
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
            // Unit tests use the app as host: keep it passive (no polling, no panels).
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
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
