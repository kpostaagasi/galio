import SwiftUI

/// Size of the overlay content, reported to the panel controller (which resizes the panel).
struct OverlaySizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Root view of the floating overlay. Content follows the game flow.
struct OverlayView: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var overlay: OverlayController
    @AppStorage(OverlayController.clickThroughKey) private var clickThrough = false
    @AppStorage(OverlayController.expandedKey) private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 10 : 7) {
            header
            Divider().opacity(0.4)
            content
        }
        .padding(expanded ? 12 : 10)
        .frame(width: expanded ? OverlayController.expandedWidth : OverlayController.compactWidth, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: OverlaySizeKey.self, value: g.size) })
        .onPreferenceChange(OverlaySizeKey.self) { size in
            Task { @MainActor in OverlayController.shared.contentSizeChanged(size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.mode?.title ?? "Galio").font(expanded ? .headline : .subheadline.weight(.semibold)).lineLimit(1)
                Text(session.phase.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                expanded.toggle()
            } label: {
                Image(systemName: expanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
            .help(expanded ? Text("Sade görünüm") : Text("Ayrıntılı görünüm"))
            .accessibilityLabel(expanded ? Text("Sade görünüm") : Text("Ayrıntılı görünüm"))
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
