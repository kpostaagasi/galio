import Foundation

/// Everything shown during champion select, computed from visible state only.
struct ChampSelectAdvice {
    let mode: ModeInfo
    let position: Position?
    let champion: ChampionInfo?
    let locked: Bool
    let suggestions: [ChampionSuggestion]
    let runes: [RunePageSuggestion]
    let spells: [SpellSuggestion]
    let skill: SkillPlan?
    let build: BuildData?
    let buildKey: String
    let allies: [ChampionInfo]
    let enemies: [ChampionInfo]
    let threat: EnemyThreat
    let currentSpells: [Int]
}

/// Everything shown in game.
struct InGameAdvice {
    let mode: ModeInfo
    let champion: ChampionInfo?
    let level: Int
    let gold: Double
    let skill: SkillPlan?
    let nextSkill: String?
    let currentRanks: [String: Int]
    let items: [ItemSuggestion]
    let owned: [Int]
    let threat: EnemyThreat
    let allies: [ChampionInfo]
    let enemies: [ChampionInfo]
    let augments: [AugmentRating]
    let build: BuildData?
}

enum AdviceBuilder {
    static func buildKey(mode: ModeInfo, position: Position?, champion: ChampionInfo?) -> String {
        if mode.usesAramBuild { return "ARAM" }
        if let position { return position.rawValue }
        return champion?.positions.first ?? "MIDDLE"
    }

    @MainActor
    static func champSelect(session: GameSession, store: DataStore) -> ChampSelectAdvice? {
        guard let cs = session.champSelect, let data = store.data else { return nil }
        let mode = session.mode ?? ModeInfo.classify(gameMode: nil, queueId: nil, mapId: 11, isCustom: cs.isCustomGame, isRanked: false)
        let allies = cs.allyChampionIds.compactMap { store.champion(key: $0) }
        let enemies = cs.visibleEnemyChampionIds.compactMap { store.champion(key: $0) }
        let mine = store.champion(key: cs.myChampionId)
        var swapPool: [ChampionInfo] = []
        if cs.benchEnabled {
            swapPool = ([cs.myChampionId] + cs.benchChampionIds).compactMap { store.champion(key: $0) }
        }
        let ctx = ChampSelectContext(mode: mode, position: cs.myPosition, allies: allies, enemies: enemies,
                                     unavailable: cs.unavailableChampionIds.subtracting([cs.myChampionId]),
                                     pickable: session.pickableChampionIds, swapPool: swapPool, mastery: session.mastery)
        let suggestions = ChampionAdvisor.suggest(ctx, from: data.champions)
        return make(mode: mode, position: cs.myPosition, champion: mine, locked: cs.isMyPickLocked, suggestions: suggestions,
                    allies: allies, enemies: enemies, store: store, currentSpells: [cs.me?.spell1Id ?? 0, cs.me?.spell2Id ?? 0])
    }

    /// Static champion page (no live context), used by the champion browser.
    @MainActor
    static func championPage(_ champion: ChampionInfo, key: String, store: DataStore) -> ChampSelectAdvice {
        let family: ModeFamily = key == "ARAM" ? .aram : .summonersRift
        let mode = ModeInfo(family: family, queueId: nil, gameMode: key == "ARAM" ? "ARAM" : "CLASSIC",
                            mapId: key == "ARAM" ? 12 : 11, isRanked: false, isCustom: false, isDraft: key != "ARAM")
        return make(mode: mode, position: Position(rawValue: key), champion: champion, locked: true, suggestions: [],
                    allies: [], enemies: [], store: store, currentSpells: [])
    }

    @MainActor
    static func make(mode: ModeInfo, position: Position?, champion: ChampionInfo?, locked: Bool, suggestions: [ChampionSuggestion],
                     allies: [ChampionInfo], enemies: [ChampionInfo], store: DataStore, currentSpells: [Int]) -> ChampSelectAdvice {
        let key = buildKey(mode: mode, position: position, champion: champion)
        let detail = champion.flatMap { store.detail(for: $0) }
        let build = detail?.build(for: key)
        let threat = EnemyThreat(champions: enemies)
        var runes: [RunePageSuggestion] = []
        var spells: [SpellSuggestion] = []
        if let champion, let build {
            runes = RuneAdvisor.suggest(build: build, champion: champion, enemies: enemies, mode: mode)
            if let set = store.data { runes = runes.filter { RuneAdvisor.isValid($0, runes: set.runes) } }
            spells = SummonerSpellAdvisor.suggest(build: build, champion: champion, position: position ?? Position(rawValue: key),
                                                  enemies: enemies, mode: mode)
        }
        return ChampSelectAdvice(mode: mode, position: position, champion: champion, locked: locked, suggestions: suggestions,
                                 runes: runes, spells: spells, skill: detail.map { SkillOrderAdvisor.plan(for: $0.skillOrder) },
                                 build: build, buildKey: key, allies: allies, enemies: enemies, threat: threat,
                                 currentSpells: currentSpells)
    }

    @MainActor
    static func inGame(session: GameSession, store: DataStore) -> InGameAdvice? {
        guard let live = session.live, let me = live.me else { return nil }
        let mode = session.mode ?? live.mode
        let champion = store.champion(liveId: me.championDataId, name: me.championName)
        let allies = live.allies.compactMap { store.champion(liveId: $0.championDataId, name: $0.championName) }
        var enemies: [ChampionInfo] = []
        var enemyItems: [[ItemInfo]] = []
        for p in live.enemies {
            guard let c = store.champion(liveId: p.championDataId, name: p.championName) else { continue }
            enemies.append(c)
            enemyItems.append(p.itemIds.compactMap { store.itemsById[$0] })
        }
        let threat = EnemyThreat(champions: enemies, items: enemyItems)
        let detail = champion.flatMap { store.detail(for: $0) }
        let position = Position(lcu: me.position) ?? session.champSelect?.myPosition
        let build = detail?.build(for: buildKey(mode: mode, position: position, champion: champion))
        let plan = detail.map { SkillOrderAdvisor.plan(for: $0.skillOrder) }
        let ranks: [String: Int] = ["Q": live.activePlayer?.abilityLevel("Q") ?? 0, "W": live.activePlayer?.abilityLevel("W") ?? 0,
                                    "E": live.activePlayer?.abilityLevel("E") ?? 0, "R": live.activePlayer?.abilityLevel("R") ?? 0]
        let level = live.activePlayer?.level ?? me.level
        let next = plan.flatMap { SkillOrderAdvisor.nextSkill(plan: $0, level: level, current: ranks) }
        let gold = live.activePlayer?.currentGold ?? 0
        var items: [ItemSuggestion] = []
        if let build {
            items = ItemAdvisor.suggest(build: build, owned: me.itemIds, gold: gold, threat: threat, items: store.itemsById, map: mode.itemMap)
        }
        var augments: [AugmentRating] = []
        if mode.hasAugments, let champion {
            augments = AugmentAdvisor.rank(store.augments(for: mode), champion: champion, archetype: build?.archetype)
        }
        return InGameAdvice(mode: mode, champion: champion, level: level, gold: gold, skill: plan, nextSkill: next,
                            currentRanks: ranks, items: items, owned: me.itemIds, threat: threat, allies: allies,
                            enemies: enemies, augments: augments, build: build)
    }
}
