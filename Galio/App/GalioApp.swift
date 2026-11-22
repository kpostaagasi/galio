import SwiftUI

@main
struct GalioApp: App {
    @StateObject private var monitor = ClientMonitor()

    var body: some Scene {
        WindowGroup("Galio", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 520, minHeight: 360)
                .onAppear { monitor.start() }
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
        } label: {
            Image(systemName: "shield.lefthalf.filled")
        }
    }
}
