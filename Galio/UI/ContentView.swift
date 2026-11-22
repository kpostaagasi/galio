import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case live, champions, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return Loc.tr("Canlı")
        case .champions: return Loc.tr("Şampiyonlar")
        case .history: return Loc.tr("Geçmiş")
        case .about: return Loc.tr("Hakkında")
        }
    }

    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .champions: return "person.crop.square"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @State private var selection: SidebarItem? = .live

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                ConnectionBadge()
                    .padding(10)
            }
        } detail: {
            switch selection ?? .live {
            case .live: LiveView()
            case .champions: ChampionsView()
            case .history: HistoryView()
            case .about: AboutView()
            }
        }
    }
}

struct ConnectionBadge: View {
    @EnvironmentObject private var session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.connection.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusTitle).font(.caption.weight(.semibold))
                Text(session.phase.title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch session.connection {
        case .clientClosed: return Loc.tr("İstemci kapalı")
        case .connected: return Loc.tr("İstemci bağlı")
        case .mock(let name): return Loc.tr("Deneme modu: %@", name)
        }
    }
}

/// Main "Live" page: follows the current phase with the full-size version of the overlay content.
struct LiveView: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.mode?.title ?? "Galio").font(.largeTitle.bold())
                        Text(session.phase.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                switch session.phase {
                case .champSelect:
                    ChampSelectPage()
                case .inProgress, .reconnect, .gameStart:
                    InGamePage()
                case .waitingForStats, .preEndOfGame, .endOfGame:
                    PostGamePage()
                default:
                    IdlePage()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IdlePage: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                if session.connection.isConnected {
                    Label("League istemcisine bağlanıldı", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Text("Bir sıraya gir — şampiyon seçimi başladığında öneriler burada ve oyun içi katmanda görünecek.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("League istemcisi kapalı", systemImage: "moon.zzz.fill")
                        .font(.headline)
                    Text("League of Legends'ı açtığında Galio otomatik bağlanır. Oyun içi katman için oyunu Kenarlıksız ya da Pencere modunda çalıştır.")
                        .foregroundStyle(.secondary)
                }
            }
            Card {
                Label("Veri", systemImage: "externaldrive.fill").font(.headline)
                Text(Loc.tr("Yama %@ · %@ şampiyon · kaynak: %@", store.patch, String(store.data?.champions.count ?? 0), store.source.rawValue))
                    .foregroundStyle(.secondary)
                if let err = store.refreshError {
                    Text(Loc.tr("Güncelleme başarısız: %@", err)).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}
