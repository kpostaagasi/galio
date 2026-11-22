import Foundation

/// A rune page as returned by `/lol-perks/v1/pages`.
struct LCUPerkPage: Decodable, Equatable {
    let id: Int
    let name: String
    let isDeletable: Bool
    let isEditable: Bool
    let current: Bool

    enum CodingKeys: String, CodingKey { case id, name, isDeletable, isEditable, current }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientInt(.id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        isDeletable = (try? c.decodeIfPresent(Bool.self, forKey: .isDeletable)) ?? false
        isEditable = (try? c.decodeIfPresent(Bool.self, forKey: .isEditable)) ?? false
        current = (try? c.decodeIfPresent(Bool.self, forKey: .current)) ?? false
    }
}

struct LCUPerkInventory: Decodable {
    let ownedPageCount: Int
}

struct NewPerkPage: Encodable, Equatable {
    let name: String
    let primaryStyleId: Int
    let subStyleId: Int
    let selectedPerkIds: [Int]
    let current: Bool
}

/// User-initiated client conveniences. Every method is only reachable from a button the player
/// clicks, and each refuses to run while the live game is in progress (Riot policy).
struct ClientActions {
    enum ActionError: Error, Equatable {
        case notAllowedInGame
        case noEditablePage
    }

    enum RuneImportOutcome: Equatable {
        case created(name: String)
        /// The page limit is full: ask the player before replacing `pageName`.
        case needsConfirmation(pageId: Int, pageName: String)
    }

    let client: LCUClient
    let phase: GameflowPhase

    private func ensureAllowed() throws {
        guard phase.allowsClientActions else { throw ActionError.notAllowedInGame }
    }

    static func isGalioPage(_ name: String) -> Bool { name.hasPrefix("Galio") }

    /// Creates (or replaces Galio's previous) rune page and makes it current.
    /// When the page limit is full and Galio has no page yet, returns `.needsConfirmation`
    /// unless `replacing` names the page the player agreed to overwrite.
    func importRunes(_ page: NewPerkPage, replacing: Int? = nil) async throws -> RuneImportOutcome {
        try ensureAllowed()
        var pages: [LCUPerkPage] = try await client.get("/lol-perks/v1/pages")
        for old in pages where Self.isGalioPage(old.name) && old.isDeletable {
            try await client.request("DELETE", "/lol-perks/v1/pages/\(old.id)")
        }
        pages.removeAll { Self.isGalioPage($0.name) && $0.isDeletable }
        let custom = pages.filter(\.isDeletable)
        let owned = (try? await client.get("/lol-perks/v1/inventory", as: LCUPerkInventory.self).ownedPageCount) ?? Int.max
        if custom.count >= owned {
            if let target = replacing, custom.contains(where: { $0.id == target }) {
                try await client.request("DELETE", "/lol-perks/v1/pages/\(target)")
            } else {
                guard let victim = custom.first(where: \.current) ?? custom.first else { throw ActionError.noEditablePage }
                return .needsConfirmation(pageId: victim.id, pageName: victim.name)
            }
        }
        let data = try await client.send("POST", "/lol-perks/v1/pages", body: page)
        if let created = try? JSONDecoder().decode(LCUPerkPage.self, from: data), created.id != 0 {
            _ = try? await client.send("PUT", "/lol-perks/v1/currentpage", body: created.id)
        }
        return .created(name: page.name)
    }

    /// Sets summoner spells in champ select (`PATCH /lol-champ-select/v1/session/my-selection`).
    func setSummonerSpells(_ spells: [Int]) async throws {
        try ensureAllowed()
        guard spells.count == 2 else { return }
        struct Selection: Encodable { let spell1Id: Int; let spell2Id: Int }
        try await client.send("PATCH", "/lol-champ-select/v1/session/my-selection", body: Selection(spell1Id: spells[0], spell2Id: spells[1]))
    }

    /// Writes a "Galio: <champion>" item set via the client's item-set API, replacing Galio's
    /// previous set for that champion and keeping all of the player's own sets.
    func exportItemSet(_ set: ItemSetPayload) async throws {
        try ensureAllowed()
        let me = try await client.currentSummoner()
        let path = "/lol-item-sets/v1/item-sets/\(me.summonerId)/sets"
        let raw = try await client.request("GET", path)
        var root = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
        var sets = root["itemSets"] as? [[String: Any]] ?? []
        sets.removeAll { ($0["title"] as? String) == set.title }
        sets.append(set.json)
        root["itemSets"] = sets
        if root["accountId"] == nil, let acc = me.accountId { root["accountId"] = acc }
        root["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
        let body = try JSONSerialization.data(withJSONObject: root)
        try await client.request("PUT", path, json: body)
    }
}

/// Item set in the League client's JSON format.
struct ItemSetPayload: Equatable {
    struct Block: Equatable {
        let type: String
        let items: [Int]
    }

    let title: String
    let championKey: Int
    let map: Int
    let blocks: [Block]

    var json: [String: Any] {
        [
            "title": title,
            "associatedChampions": [championKey],
            "associatedMaps": [map],
            "blocks": blocks.map { b in
                ["type": b.type, "items": b.items.map { ["id": String($0), "count": 1] }] as [String: Any]
            },
            "map": "any",
            "mode": "any",
            "preferredItemSlots": [Any](),
            "sortrank": 0,
            "startedFrom": "blank",
            "type": "custom",
            "uid": UUID().uuidString.lowercased(),
        ]
    }

    static func from(build: BuildData, champion: ChampionInfo, position: String, map: Int, threat: EnemyThreat) -> ItemSetPayload {
        var blocks: [Block] = []
        if !build.items.starter.isEmpty { blocks.append(Block(type: Loc.tr("Başlangıç"), items: build.items.starter)) }
        let core = Array(build.items.core.prefix(3))
        if !core.isEmpty { blocks.append(Block(type: Loc.tr("Temel eşyalar"), items: Array(build.items.boots.prefix(1)) + core)) }
        let later = Array(build.items.core.dropFirst(3))
        if !later.isEmpty { blocks.append(Block(type: Loc.tr("Geç oyun"), items: later)) }
        let situational = build.items.situational.map(\.id).filter { !build.items.core.contains($0) }
        if !situational.isEmpty { blocks.append(Block(type: Loc.tr("Duruma göre"), items: situational)) }
        return ItemSetPayload(title: String("Galio: \(champion.name) \(position)".prefix(40)), championKey: champion.key, map: map, blocks: blocks)
    }
}
