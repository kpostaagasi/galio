import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: ClientMonitor

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Sürüm \(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Galio").font(.largeTitle.bold())
                    Text("League of Legends yardımcısı").foregroundStyle(.secondary)
                }
            }

            StatusCard(status: monitor.status)

            VStack(alignment: .leading, spacing: 6) {
                Text("Yakında").font(.headline)
                Label("Şampiyon seçiminde takımına göre öneriler", systemImage: "person.3")
                Label("Rün sayfası önerisi ve tek tıkla aktarma", systemImage: "circle.hexagongrid")
                Label("Yetenek sırası ve karşı takıma göre eşyalar", systemImage: "bag")
            }
            .foregroundStyle(.secondary)

            Spacer()
            Text(version).font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(28)
    }
}

struct StatusCard: View {
    let status: ClientMonitor.Status

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.isOpen ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.headline)
                Text(status.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
