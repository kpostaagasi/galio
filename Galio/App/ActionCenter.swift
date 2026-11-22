import Foundation

/// Runs the user-initiated client actions (rune import, summoner spells, item-set export) and
/// reports their outcome. Nothing here runs without a click, and nothing runs in game.
@MainActor
final class ActionCenter: ObservableObject {
    static let shared = ActionCenter()

    struct PendingReplace: Identifiable, Equatable {
        let page: NewPerkPage
        let pageId: Int
        let pageName: String
        var id: Int { pageId }
    }

    @Published var message: String?
    @Published var isError = false
    @Published var busy = false
    @Published var pendingReplace: PendingReplace?

    private func actions() -> ClientActions? {
        let session = GameSession.shared
        guard let lcu = session.lcu else {
            report(Loc.tr("League istemcisine bağlı değil"), error: true)
            return nil
        }
        guard session.phase.allowsClientActions else {
            report(Loc.tr("Oyun sırasında istemci işlemi yapılmaz"), error: true)
            return nil
        }
        return ClientActions(client: lcu, phase: session.phase)
    }

    func report(_ text: String, error: Bool = false) {
        message = text
        isError = error
        let shown = text
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self.message == shown { self.message = nil }
        }
    }

    func importRunes(_ suggestion: RunePageSuggestion, champion: ChampionInfo) {
        let page = NewPerkPage(name: suggestion.importName(champion: champion), primaryStyleId: suggestion.primaryStyleId,
                               subStyleId: suggestion.subStyleId, selectedPerkIds: suggestion.perkIds, current: true)
        run(page: page, replacing: nil)
    }

    func confirmReplace() {
        guard let pending = pendingReplace else { return }
        pendingReplace = nil
        run(page: pending.page, replacing: pending.pageId)
    }

    private func run(page: NewPerkPage, replacing: Int?) {
        guard let actions = actions() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                switch try await actions.importRunes(page, replacing: replacing) {
                case .created(let name):
                    report(Loc.tr("Rün sayfası aktarıldı: %@", name))
                case .needsConfirmation(let id, let name):
                    pendingReplace = PendingReplace(page: page, pageId: id, pageName: name)
                }
            } catch {
                report(Loc.tr("Rün sayfası aktarılamadı: %@", error.localizedDescription), error: true)
            }
        }
    }

    func setSpells(_ spells: [Int], current: [Int]) {
        guard let actions = actions() else { return }
        let ordered = SummonerSpellAdvisor.orderForPlayer(spells, currentSpell1: current.first ?? 0, currentSpell2: current.dropFirst().first ?? 0)
        busy = true
        Task {
            defer { busy = false }
            do {
                try await actions.setSummonerSpells(ordered)
                report(Loc.tr("Sihirdar büyüleri ayarlandı"))
                await GameSession.shared.refreshChampSelect()
            } catch {
                report(Loc.tr("Büyüler ayarlanamadı: %@", error.localizedDescription), error: true)
            }
        }
    }

    func exportItemSet(_ payload: ItemSetPayload) {
        guard let actions = actions() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await actions.exportItemSet(payload)
                report(Loc.tr("Eşya seti istemciye yazıldı: %@", payload.title))
            } catch {
                report(Loc.tr("Eşya seti yazılamadı: %@", error.localizedDescription), error: true)
            }
        }
    }
}
