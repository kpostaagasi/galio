import SwiftUI

struct ChampSelectPage: View {
    var body: some View {
        Card { ChampSelectOverlay() }
    }
}

struct InGamePage: View {
    var body: some View {
        Card { InGameOverlay() }
    }
}

struct PostGamePage: View {
    var body: some View {
        Card { PostGameOverlay() }
    }
}

struct ChampionsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var query = ""

    private var champions: [ChampionInfo] {
        let all = store.data?.champions ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) || $0.nameTR.lowercased().contains(q) }
        return list.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List(champions) { champ in
            HStack {
                ChampionChip(champion: champ, size: 28)
                Spacer()
                Text(champ.positionList.map(\.title).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: Text("Şampiyon ara"))
        .navigationTitle("Şampiyonlar")
    }
}

struct HistoryView: View {
    var body: some View {
        ContentUnavailableView("Henüz oyun yok", systemImage: "clock",
                               description: Text("Bitirdiğin oyunların özetleri burada listelenecek."))
    }
}
