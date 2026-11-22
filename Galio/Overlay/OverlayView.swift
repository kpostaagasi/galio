import SwiftUI

/// Root view of the floating overlay. Content follows the game flow.
struct OverlayView: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var overlay: OverlayController
    @AppStorage(OverlayController.clickThroughKey) private var clickThrough = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.4)
            content
        }
        .padding(12)
        .frame(width: 340, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.mode?.title ?? "Galio").font(.headline)
                Text(session.phase.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                overlay.setClickThrough(!clickThrough)
            } label: {
                Image(systemName: clickThrough ? "cursorarrow.slash" : "cursorarrow")
            }
            .buttonStyle(.borderless)
            .help("Tıklama geçirgenliği (kısayol ⌥⇧G ile gizle/göster)")
            .accessibilityLabel("Tıklama geçirgenliği")
            Button {
                overlay.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Katmanı gizle (⌥⇧G)")
            .accessibilityLabel("Katmanı gizle")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .champSelect:
            ChampSelectOverlay()
        case .inProgress, .reconnect:
            InGameOverlay()
        case .gameStart:
            LoadingOverlay()
        case .waitingForStats, .preEndOfGame, .endOfGame:
            PostGameOverlay()
        default:
            IdleOverlay()
        }
    }
}

struct IdleOverlay: View {
    @EnvironmentObject private var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (session.connection.isConnected
                ? Text("İstemci bağlı. Şampiyon seçimi başlayınca öneriler burada görünecek.")
                : Text("League istemcisi bekleniyor…"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LoadingOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChampionChip(champion: session.myChampion(in: store), size: 32)
            Text("Yükleme ekranı — oyun başlayınca yetenek sırası ve eşya önerileri gelecek.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Row of champion icons for a team (no player names, ever).
struct TeamStrip: View {
    let title: String
    let champions: [ChampionInfo?]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            if champions.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            }
            ForEach(Array(champions.enumerated()), id: \.offset) { _, champ in
                ChampionChip(champion: champ, size: size, showName: false)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + ": " + champions.map { $0?.displayName ?? "—" }.joined(separator: ", "))
    }
}
