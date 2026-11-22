#!/usr/bin/env python3
"""Generate recorded-style LCU / Live Client fixtures and mock scenarios.

The shapes follow the League Client API and Live Client Data API responses (field names and
nesting as returned by the real endpoints; identity fields of other players are blanked the way
ranked champ select hides them). Output:
  Galio/Resources/Mock/<scenario>.json   (served by MockServer for --mock-game)
  GalioTests/Fixtures/*.json             (single responses used by unit tests)
"""
import copy
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCK = ROOT / "Galio" / "Resources" / "Mock"
FIX = ROOT / "GalioTests" / "Fixtures"

C = dict(Garen=86, LeeSin=64, Jinx=222, Thresh=412, Galio=3, Malphite=54, Vi=254, Zed=238, Caitlyn=51,
         Soraka=16, Lux=99, Ahri=103, Darius=122, Yasuo=157, Ezreal=81, Leona=89, Orianna=61, Sejuani=113,
         Pyke=555, Kaisa=145, Nautilus=111, Brand=63, Jax=24, Katarina=55, Sona=37, Vayne=67, Mordekaiser=82,
         Amumu=32, MissFortune=21, Veigar=45, Nami=267, Samira=360, Sett=875, Ashe=22)
FLASH, IGNITE, TP, SMITE, HEAL, EXHAUST, BARRIER, MARK, CLEANSE, GHOST = 4, 14, 12, 11, 7, 3, 21, 32, 1, 6


def player(cell, champ, pos="", intent=0, team=1, s1=FLASH, s2=IGNITE, hidden=False):
    return {
        "assignedPosition": pos, "cellId": cell, "championId": champ, "championPickIntent": intent,
        "nameVisibilityType": "HIDDEN" if hidden else "VISIBLE", "obfuscatedPuuid": "", "obfuscatedSummonerId": 0,
        "puuid": "", "selectedSkinId": champ * 1000 if champ else 0, "spell1Id": s1, "spell2Id": s2,
        "summonerId": 0, "team": team, "wardSkinId": -1, "gameName": "", "tagLine": "", "internalName": "",
        "playerType": "PLAYER", "isHumanoid": False,
    }


def action(aid, cell, champ, typ, completed, in_progress=False, ally=True):
    return {"actorCellId": cell, "championId": champ, "completed": completed, "id": aid,
            "isAllyAction": ally, "isInProgress": in_progress, "pickTurn": 1, "type": typ}


def gameflow_session(queue_id, game_mode, map_id, phase, ranked, custom=False, qtype="NORMAL", desc=""):
    return {
        "phase": phase,
        "gameClient": {"running": phase in ("InProgress", "GameStart"), "serverIp": "", "serverPort": 0, "visible": False},
        "gameData": {"gameId": 7300000000 + queue_id, "isCustomGame": custom, "gameName": "",
                     "queue": {"id": queue_id, "gameMode": game_mode, "mapId": map_id, "type": qtype,
                               "description": desc, "isRanked": ranked, "category": "Custom" if custom else "PvP"},
                     "teamOne": [], "teamTwo": [], "playerChampionSelections": []},
        "map": {"id": map_id, "gameMode": game_mode, "name": {11: "Summoner's Rift", 12: "Howling Abyss", 30: "Rings of Wrath"}.get(map_id, "")},
    }


def perks_pages():
    return [
        {"id": 101, "name": "Mid Mage", "current": True, "isDeletable": True, "isEditable": True, "isActive": True,
         "primaryStyleId": 8100, "subStyleId": 8200, "selectedPerkIds": [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5001],
         "order": 0, "isValid": True},
        {"id": 102, "name": "Tank Top", "current": False, "isDeletable": True, "isEditable": True, "isActive": False,
         "primaryStyleId": 8400, "subStyleId": 8300, "selectedPerkIds": [8437, 8446, 8429, 8451, 8304, 8347, 5008, 5001, 5011],
         "order": 1, "isValid": True},
        {"id": 50, "name": "Recommended (Riot)", "current": False, "isDeletable": False, "isEditable": False,
         "isActive": False, "primaryStyleId": 8000, "subStyleId": 8100, "selectedPerkIds": [8010, 9111, 9104, 8014, 8139, 8135, 5005, 5008, 5001],
         "order": 2, "isValid": True},
    ]


def champ_select(locked=False):
    me = player(2, C["Galio"] if locked else 0, "middle", intent=0)
    my_team = [player(0, C["Garen"], "top", s2=TP), player(1, C["LeeSin"], "jungle", s2=SMITE), me,
               player(3, 0, "bottom", intent=C["Jinx"], s2=HEAL), player(4, 0, "utility", intent=C["Thresh"])]
    if locked:
        my_team[3] = player(3, C["Jinx"], "bottom", s2=HEAL)
        my_team[4] = player(4, C["Thresh"], "utility")
    enemies = [player(5, C["Malphite"], "", team=2, hidden=True), player(6, C["Vi"], "", team=2, hidden=True),
               player(7, C["Zed"], "", team=2, hidden=True), player(8, C["Caitlyn"] if locked else 0, "", team=2, hidden=True),
               player(9, C["Soraka"] if locked else 0, "", team=2, hidden=True)]
    bans = [action(1, 0, C["Yasuo"], "ban", True), action(2, 1, C["Darius"], "ban", True), action(3, 2, C["Pyke"], "ban", True),
            action(4, 3, C["Samira"], "ban", True), action(5, 4, C["Nautilus"], "ban", True),
            action(6, 5, C["Kaisa"], "ban", True, ally=False), action(7, 6, C["Katarina"], "ban", True, ally=False),
            action(8, 7, C["Sett"], "ban", True, ally=False), action(9, 8, C["Vayne"], "ban", True, ally=False),
            action(10, 9, C["Veigar"], "ban", True, ally=False)]
    picks = [[action(11, 0, C["Garen"], "pick", True)], [action(12, 5, C["Malphite"], "pick", True, ally=False),
             action(13, 6, C["Vi"], "pick", True, ally=False)], [action(14, 1, C["LeeSin"], "pick", True),
             action(15, 2, C["Galio"] if locked else 0, "pick", locked, in_progress=not locked)],
             [action(16, 7, C["Zed"], "pick", True, ally=False), action(17, 8, C["Caitlyn"] if locked else 0, "pick", locked, ally=False)],
             [action(18, 3, C["Jinx"] if locked else 0, "pick", locked), action(19, 4, C["Thresh"] if locked else 0, "pick", locked)],
             [action(20, 9, C["Soraka"] if locked else 0, "pick", locked, ally=False)]]
    return {
        "actions": [bans] + picks, "allowBattleBoost": False, "allowDuplicatePicks": False, "allowLockedEvents": False,
        "allowRerolling": False, "allowSkinSelection": True, "bans": {"myTeamBans": [], "numBans": 10, "theirTeamBans": []},
        "benchChampions": [], "benchEnabled": False, "boostableSkinCount": 1, "chatDetails": {"mucJwtDto": {}},
        "counter": 12, "gameId": 7300000420, "hasSimultaneousBans": True, "hasSimultaneousPicks": False,
        "isCustomGame": False, "isSpectating": False, "localPlayerCellId": 2, "lockedEventIndex": -1,
        "myTeam": my_team, "pickOrderSwaps": [], "recoveryCounter": 0, "rerollsRemaining": 0, "skipChampionSelect": False,
        "theirTeam": enemies,
        "timer": {"adjustedTimeLeftInPhase": 21000 if locked else 27000, "internalNowInEpochMs": 1795000000000,
                  "isInfinite": False, "phase": "FINALIZATION" if locked else "BAN_PICK", "totalTimeInPhase": 30000},
        "trades": [],
    }


def item(iid, name, slot, price=0, count=1):
    return {"canUse": False, "consumable": False, "count": count, "displayName": name, "itemID": iid, "price": price,
            "rawDescription": f"GeneratedTip_Item_{iid}_Description", "rawDisplayName": f"Item_{iid}_Name", "slot": slot}


def live_player(champ_name, raw_id, team, level, items, k, d, a, cs, pos="", me=False, name=None):
    gn = name if me else ""
    return {
        "championName": champ_name, "isBot": False, "isDead": False, "items": items, "level": level,
        "position": pos, "rawChampionName": f"game_character_displayname_{raw_id}", "rawSkinName": "",
        "respawnTimer": 0.0, "riotId": f"{gn}#TR1" if me else "", "riotIdGameName": gn, "riotIdTagLine": "TR1" if me else "",
        "runes": {"keystone": {"displayName": "", "id": 0}, "primaryRuneTree": {"displayName": "", "id": 0},
                  "secondaryRuneTree": {"displayName": "", "id": 0}},
        "scores": {"assists": a, "creepScore": cs, "deaths": d, "kills": k, "wardScore": 7.5},
        "skinID": 0, "summonerName": f"{gn}#TR1" if me else "",
        "summonerSpells": {"summonerSpellOne": {"displayName": "Flash"}, "summonerSpellTwo": {"displayName": "Ignite"}},
        "team": team,
    }


def active_player(name, level, gold, q, w, e, r, champ_name):
    return {
        "abilities": {"E": {"abilityLevel": e, "displayName": "E"}, "Passive": {"displayName": "Passive"},
                      "Q": {"abilityLevel": q, "displayName": "Q"}, "R": {"abilityLevel": r, "displayName": "R"},
                      "W": {"abilityLevel": w, "displayName": "W"}},
        "championStats": {"abilityPower": 95.0, "armor": 48.0, "attackDamage": 70.0, "currentHealth": 1220.0,
                          "magicResist": 52.0, "maxHealth": 1400.0, "moveSpeed": 385.0},
        "currentGold": gold, "fullRunes": {}, "level": level,
        "riotId": f"{name}#TR1", "riotIdGameName": name, "riotIdTagLine": "TR1", "summonerName": f"{name}#TR1",
        "teamRelativeColors": True,
    }


def live_game(mode, map_number, game_time, me, allies, enemies, active):
    return {"activePlayer": active, "allPlayers": [me] + allies + enemies,
            "events": {"Events": [{"EventID": 0, "EventName": "GameStart", "EventTime": 0.05}]},
            "gameData": {"gameMode": mode, "gameTime": game_time, "mapName": f"Map{map_number}", "mapNumber": map_number,
                         "mapTerrain": "Default"}}


SR_INGAME = live_game(
    "CLASSIC", 11, 1012.4,
    live_player("Galio", "Galio", "ORDER", 9, [item(1056, "Doran's Ring", 0, 400), item(3111, "Mercury's Treads", 1, 1250),
                                               item(1052, "Amplifying Tome", 2, 400), item(3340, "Stealth Ward", 6)], 2, 1, 6, 98, "MIDDLE", me=True, name="Galio Fan"),
    [live_player("Garen", "Garen", "ORDER", 9, [item(3071, "Black Cleaver", 0, 3000)], 1, 2, 2, 110, "TOP"),
     live_player("Lee Sin", "LeeSin", "ORDER", 8, [item(1102, "Gustwalker Hatchling", 0, 450)], 3, 2, 4, 70, "JUNGLE"),
     live_player("Jinx", "Jinx", "ORDER", 8, [item(3032, "Yun Tal Wildarrows", 0, 3000)], 2, 1, 3, 105, "BOTTOM"),
     live_player("Thresh", "Thresh", "ORDER", 6, [item(3865, "World Atlas", 0, 400)], 0, 2, 8, 12, "UTILITY")],
    [live_player("Malphite", "Malphite", "CHAOS", 9, [item(3068, "Sunfire Aegis", 0, 2800), item(3047, "Plated Steelcaps", 1, 1200)], 1, 2, 3, 102, "TOP"),
     live_player("Vi", "Vi", "CHAOS", 8, [item(3071, "Black Cleaver", 0, 3000)], 2, 3, 2, 65, "JUNGLE"),
     live_player("Zed", "Zed", "CHAOS", 9, [item(3142, "Youmuu's Ghostblade", 0, 2800), item(6698, "Profane Hydra", 1, 2850)], 4, 2, 1, 101, "MIDDLE"),
     live_player("Caitlyn", "Caitlyn", "CHAOS", 8, [item(3031, "Infinity Edge", 0, 3500), item(3006, "Berserker's Greaves", 1, 1100)], 1, 1, 2, 118, "BOTTOM"),
     live_player("Soraka", "Soraka", "CHAOS", 7, [item(6617, "Moonstone Renewer", 0, 2200)], 0, 1, 5, 15, "UTILITY")],
    active_player("Galio Fan", 9, 1640.0, 5, 1, 3, 1, "Galio"),
)

MAYHEM_INGAME = live_game(
    "KIWI", 12, 420.0,
    live_player("Lux", "Lux", "ORDER", 11, [item(6655, "Luden's Echo", 0, 2750), item(3020, "Sorcerer's Shoes", 1, 1100)], 5, 2, 9, 40, me=True, name="Galio Fan"),
    [live_player("Sejuani", "Sejuani", "ORDER", 11, [], 1, 3, 10, 30), live_player("Ezreal", "Ezreal", "ORDER", 11, [], 4, 2, 6, 44),
     live_player("Sona", "Sona", "ORDER", 10, [], 0, 3, 14, 20), live_player("Jax", "Jax", "ORDER", 11, [], 6, 4, 3, 38)],
    [live_player("Mordekaiser", "Mordekaiser", "CHAOS", 12, [item(4633, "Riftmaker", 0, 3100)], 6, 3, 4, 41),
     live_player("Katarina", "Katarina", "CHAOS", 11, [item(3115, "Nashor's Tooth", 0, 2900)], 7, 5, 2, 35),
     live_player("Brand", "Brand", "CHAOS", 11, [item(6653, "Liandry's Torment", 0, 3000)], 3, 4, 8, 39),
     live_player("Amumu", "Amumu", "CHAOS", 10, [item(3068, "Sunfire Aegis", 0, 2800)], 1, 4, 11, 28),
     live_player("Veigar", "Veigar", "CHAOS", 11, [item(3089, "Rabadon's Deathcap", 0, 3500)], 4, 3, 5, 42)],
    active_player("Galio Fan", 11, 860.0, 5, 2, 3, 1, "Lux"),
)

ARENA_INGAME = live_game(
    "CHERRY", 30, 610.0,
    live_player("Darius", "Darius", "ORDER", 9, [item(3071, "Black Cleaver", 0, 3000)], 3, 1, 0, 0, me=True, name="Galio Fan"),
    [live_player("Nami", "Nami", "ORDER", 9, [], 0, 1, 3, 0)],
    [live_player("Vayne", "Vayne", "CHAOS", 9, [item(3153, "Blade of The Ruined King", 0, 3200)], 2, 2, 0, 0),
     live_player("Leona", "Leona", "CHAOS", 9, [], 0, 2, 2, 0)],
    active_player("Galio Fan", 9, 400.0, 5, 1, 3, 1, "Darius"),
)

EOG = {
    "gameId": 7300000420, "gameLength": 1835, "gameMode": "CLASSIC", "queueType": "RANKED_SOLO_5x5", "gameEndedInEarlySurrender": False,
    "localPlayer": {"championId": C["Galio"], "championName": "Galio", "items": [3157, 6664, 3111, 4633, 8020, 0, 3364],
                    "spell1Id": FLASH, "spell2Id": TP, "summonerName": "", "level": 16,
                    "stats": {"ASSISTS": 14, "CHAMPIONS_KILLED": 5, "NUM_DEATHS": 3, "MINIONS_KILLED": 182, "NEUTRAL_MINIONS_KILLED": 8,
                              "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 24850, "GOLD_EARNED": 12940, "VISION_SCORE": 24, "WIN": 1,
                              "LEVEL": 16, "TOTAL_DAMAGE_TAKEN": 31200, "TOTAL_HEAL": 3200}},
    "teams": [{"isPlayerTeam": True, "isWinningTeam": True, "players": []}, {"isPlayerTeam": False, "isWinningTeam": False, "players": []}],
}

COMMON = {
    "GET /lol-summoner/v1/current-summoner": {"accountId": 2400100, "displayName": "", "gameName": "Galio Fan", "tagLine": "TR1",
                                              "puuid": "mock-puuid-local", "summonerId": 1200300, "summonerLevel": 212},
    "GET /lol-perks/v1/pages": perks_pages(),
    "GET /lol-perks/v1/inventory": {"ownedPageCount": 3, "customPageCount": 3},
    "GET /lol-item-sets/v1/item-sets/1200300/sets": {"accountId": 2400100, "itemSets": [], "timestamp": 1795000000000},
    "GET /lol-champion-mastery/v1/local-player/champion-mastery": [
        {"championId": 3, "championLevel": 12, "championPoints": 214000, "puuid": "mock-puuid-local"},
        {"championId": 61, "championLevel": 7, "championPoints": 88000, "puuid": "mock-puuid-local"},
        {"championId": 99, "championLevel": 5, "championPoints": 41000, "puuid": "mock-puuid-local"}],
    "GET /lol-champ-select/v1/pickable-champion-ids": [3, 61, 99, 103, 45, 55, 63, 37, 267, 21, 22, 86, 64, 222, 412, 54, 254, 238, 51, 16, 157, 122, 81, 89, 113, 145, 111, 24, 67, 82, 32, 360, 875, 1, 8, 13, 50, 69, 90, 101, 112, 115, 127, 134, 136, 142, 161, 163, 517, 518, 711, 800, 888, 893, 910, 950],
}


def scenario(name, desc, phase, session, extra):
    routes = dict(COMMON)
    routes["GET /lol-gameflow/v1/gameflow-phase"] = phase
    routes["GET /lol-gameflow/v1/session"] = session
    routes.update(extra)
    return {"name": name, "description": desc, "routes": routes}


def aram_select():
    cs = champ_select(locked=True)
    cs["actions"] = []
    cs["benchEnabled"] = True
    cs["benchChampions"] = [{"championId": C["Ahri"], "isPriority": False}, {"championId": C["Orianna"], "isPriority": False},
                            {"championId": C["MissFortune"], "isPriority": False}]
    cs["myTeam"] = [player(0, C["Sejuani"], s1=FLASH, s2=MARK), player(1, C["Ezreal"], s2=MARK), player(2, C["Lux"], s2=MARK),
                    player(3, C["Sona"], s2=MARK), player(4, C["Jax"], s2=MARK)]
    cs["theirTeam"] = []
    cs["timer"]["phase"] = "BAN_PICK"
    return cs


def main():
    MOCK.mkdir(parents=True, exist_ok=True)
    FIX.mkdir(parents=True, exist_ok=True)
    ranked = gameflow_session(420, "CLASSIC", 11, "ChampSelect", True, qtype="RANKED_SOLO_5x5", desc="Ranked Solo/Duo")
    scenarios = [
        scenario("champselect", "Ranked Solo/Duo champ select, local player (middle) still picking", "ChampSelect", ranked,
                 {"GET /lol-champ-select/v1/session": champ_select(False)}),
        scenario("champselect-locked", "Ranked Solo/Duo champ select, Galio locked in, all enemy picks visible", "ChampSelect", ranked,
                 {"GET /lol-champ-select/v1/session": champ_select(True)}),
        scenario("ingame", "Ranked Solo/Duo in progress, Galio mid at level 9 vs AD-heavy team with Soraka", "InProgress",
                 dict(ranked, phase="InProgress"), {"GET /liveclientdata/allgamedata": SR_INGAME}),
        scenario("aram", "ARAM champ select (bench enabled), Lux", "ChampSelect",
                 gameflow_session(450, "ARAM", 12, "ChampSelect", False, desc="ARAM"),
                 {"GET /lol-champ-select/v1/session": aram_select()}),
        scenario("mayhem", "ARAM: Mayhem in progress, Lux vs an AP-heavy team", "InProgress",
                 gameflow_session(2400, "KIWI", 12, "InProgress", False, desc="ARAM: Mayhem"),
                 {"GET /liveclientdata/allgamedata": MAYHEM_INGAME}),
        scenario("arena", "Arena (CHERRY) in progress, Darius + Nami duo", "InProgress",
                 gameflow_session(1700, "CHERRY", 30, "InProgress", False, desc="Arena"),
                 {"GET /liveclientdata/allgamedata": ARENA_INGAME}),
        scenario("postgame", "Ranked game finished, end-of-game stats available", "EndOfGame",
                 dict(ranked, phase="EndOfGame"), {"GET /lol-end-of-game/v1/eog-stats-block": EOG}),
    ]
    for s in scenarios:
        (MOCK / f"{s['name']}.json").write_text(json.dumps(s, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    fixtures = {
        "champselect-picking.json": champ_select(False),
        "champselect-locked.json": champ_select(True),
        "champselect-aram.json": aram_select(),
        "gameflow-session-ranked.json": ranked,
        "gameflow-session-mayhem.json": gameflow_session(2400, "KIWI", 12, "InProgress", False),
        "gameflow-session-arena.json": gameflow_session(1700, "CHERRY", 30, "InProgress", False),
        "gameflow-session-custom.json": gameflow_session(0, "PRACTICETOOL", 11, "InProgress", False, custom=True),
        "liveclient-sr.json": SR_INGAME,
        "liveclient-mayhem.json": MAYHEM_INGAME,
        "liveclient-arena.json": ARENA_INGAME,
        "eog-stats-block.json": EOG,
        "perks-pages.json": perks_pages(),
        "ws-gameflow-event.txt": None,
    }
    for name, obj in fixtures.items():
        if name.endswith(".txt"):
            continue
        (FIX / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (FIX / "ws-events.txt").write_text(
        '[8,"OnJsonApiEvent",{"data":"ChampSelect","eventType":"Update","uri":"/lol-gameflow/v1/gameflow-phase"}]\n'
        '[8,"OnJsonApiEvent",{"data":null,"eventType":"Delete","uri":"/lol-champ-select/v1/session"}]\n',
        encoding="utf-8")
    print("wrote", len(scenarios), "scenarios and", len(fixtures), "fixtures")


if __name__ == "__main__":
    main()
