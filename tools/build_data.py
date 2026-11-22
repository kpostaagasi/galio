#!/usr/bin/env python3
"""Build Galio's per-patch recommendation data.

Sources (all publicly distributed game data, no scraping of third-party stat sites):
  * Riot Data Dragon: versions, champions, items, runes, summoner spells (en_US + tr_TR)
  * CommunityDragon raw game data: champion roles / tactical + playstyle info,
    Riot's own in-client rune & summoner-spell recommendations, augment lists
    (Arena = CHERRY, ARAM Mayhem = KIWI) with names, rarities, tags and tooltips
  * tools/curated/*: hand-maintained skill orders, archetypes, item templates

Output:
  data/manifest.json
  data/<patch>/champions.json        compact index used by the champion advisor
  data/<patch>/champions/<Id>.json   per-champion runes, spells, skill order, builds
  data/<patch>/items.json            item stats + derived flags for the item advisor
  data/<patch>/runes.json            rune trees + stat shards (en/tr)
  data/<patch>/summoners.json        summoner spells (en/tr)
  data/<patch>/augments.json         Arena / ARAM Mayhem augments with affinity tags
  data/<patch>/all.json              everything above in one file (what the app downloads)

Usage: python3 tools/build_data.py [--patch 16.23.1] [--bundle]
  --bundle also copies all.json + manifest into Galio/Resources/BundledData/.
Optional: tools/aggregate_matches.py (needs RIOT_API_KEY) writes data/<patch>/aggregates.json,
which this script merges (skill orders / item cores observed in real matches) when present.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import shutil
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
CURATED = ROOT / "tools" / "curated"
DD = "https://ddragon.leagueoflegends.com"
CD = "https://raw.communitydragon.org/latest"
CDG = CD + "/plugins/rcp-be-lol-game-data/global"
UA = "galio-data-builder/1.0 (+https://github.com/kpostaagasi/galio)"
SCHEMA = 1

POSITIONS = ["TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY"]
SHARDS = {
    5008: ("Adaptive Force", "Uyarlanabilir Güç"),
    5005: ("Attack Speed", "Saldırı Hızı"),
    5007: ("Ability Haste", "Yetenek Hızı"),
    5010: ("Move Speed", "Hareket Hızı"),
    5001: ("Health Scaling", "Ölçeklenen Can"),
    5011: ("Health", "Can"),
    5013: ("Tenacity and Slow Resist", "Direnç ve Yavaşlatma Direnci"),
}
SHARD_ROWS = [[5008, 5005, 5007], [5008, 5010, 5001], [5011, 5013, 5001]]


def log(*a):
    print(*a, file=sys.stderr)


def fetch_json(url: str, name: str, max_age: float = 3 * 86400):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if path.exists() and time.time() - path.stat().st_mtime < max_age:
        return json.loads(path.read_text(encoding="utf-8"))
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
            path.write_bytes(raw)
            return json.loads(raw)
        except Exception as e:  # noqa: BLE001
            log(f"fetch failed ({attempt + 1}/4) {url}: {e}")
            time.sleep(2 * (attempt + 1))
    if path.exists():
        log(f"using stale cache for {url}")
        return json.loads(path.read_text(encoding="utf-8"))
    raise SystemExit(f"cannot fetch {url}")


def strip_tags(s: str) -> str:
    s = re.sub(r"<br\s*/?>", " ", s or "")
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", s).strip()


# ----------------------------------------------------------------------------- curated input

def load_curated_champions():
    table = {}
    for line in (CURATED / "champions.txt").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        cid, skill, arch = parts[0], parts[1], parts[2]
        archs = arch.split(",")
        entry = {"skill": list(skill), "archetype": archs[0], "archetypes": {}, "attrs": {}}
        for a in archs[1:]:
            pos, name = a.split(":")
            entry["archetypes"][pos] = name
        for kv in parts[3:]:
            k, v = kv.split("=")
            entry["attrs"][k] = int(v)
        table[cid] = entry
    return table


# ----------------------------------------------------------------------------- champions

def heuristic_archetype(cd):
    roles = cd.get("roles", [])
    dmg = cd.get("tacticalInfo", {}).get("damageType", "kPhysical")
    ranged = cd.get("tacticalInfo", {}).get("attackType") == "ranged"
    first = roles[0] if roles else "fighter"
    if first == "marksman":
        return "marksman"
    if first == "support":
        return "catcher" if cd.get("playstyleInfo", {}).get("durability", 1) >= 2 else "enchanter"
    if first == "tank":
        return "tankmage" if dmg == "kMagic" else "tank"
    if first == "mage":
        return "artillery" if ranged and "support" in roles else ("apassassin" if "assassin" in roles else "burstmage")
    if first == "assassin":
        return "apassassin" if dmg == "kMagic" else "assassin"
    return "apbruiser" if dmg == "kMagic" else "bruiser"


def derive_attrs(cd, dd, curated):
    ps = cd.get("playstyleInfo", {})
    roles = cd.get("roles", [])
    tags = dd.get("tags", [])
    dur, cc, mob, util, dmg = (ps.get(k, 1) for k in ("durability", "crowdControl", "mobility", "utility", "damage"))
    ranged = dd["stats"]["attackrange"] > 300
    a = {
        "frontline": min(3, dur + (1 if "tank" in roles else 0) - (1 if ranged else 0)),
        "engage": 2 if (cc >= 3 and mob >= 2) or "tank" in roles else (1 if cc >= 2 else 0),
        "peel": min(3, util + (1 if cc >= 3 and ("support" in roles or "tank" in roles) else 0)),
        "waveclear": 2 if ("mage" in roles or "marksman" in roles) else 1,
        "poke": 1 if ranged and ("mage" in roles or "marksman" in roles) else 0,
        "scaling": 2,
        "sustain": 1,
        "burst": 3 if "assassin" in roles else (2 if dmg >= 3 else 1),
        "cc": cc,
        "mobility": mob,
        "damage": dmg,
        "durability": dur,
        "utility": util,
    }
    a.update(curated.get("attrs", {}) if curated else {})
    for k in a:
        a[k] = max(0, min(3, int(a[k])))
    if "Tank" in tags and a["frontline"] < 2:
        a["frontline"] = 2
    return a


def damage_type(cd):
    return {"kMagic": "magic", "kPhysical": "physical", "kMixed": "mixed"}.get(
        cd.get("tacticalInfo", {}).get("damageType"), "physical")


# ----------------------------------------------------------------------------- items

STAT_MAP = {
    "FlatPhysicalDamageMod": "ad", "FlatMagicDamageMod": "ap", "FlatArmorMod": "armor",
    "FlatSpellBlockMod": "mr", "FlatHPPoolMod": "hp", "PercentAttackSpeedMod": "as",
    "FlatCritChanceMod": "crit", "FlatMovementSpeedMod": "ms", "PercentMovementSpeedMod": "msPct",
    "FlatMPPoolMod": "mana", "PercentLifeStealMod": "lifesteal", "FlatHPRegenMod": "hpRegen",
}

FLAG_PATTERNS = [
    ("antiheal", r"grievous wounds|\bwounds\b"),
    ("lethality", r"lethality"),
    ("armorpen", r"armor penetration"),
    ("mpen", r"magic penetration"),
    ("ah", r"ability haste"),
    ("omnivamp", r"omnivamp"),
    ("lifesteal", r"life steal"),
    ("tenacity", r"tenacity"),
    ("stasis", r"stasis"),
    ("spellshield", r"spell shield"),
    ("hsp", r"heal and shield power"),
    ("onhit", r"on-hit|attacks apply|attacks deal an additional"),
    ("antishield", r"shield reaver|reduc\w* (?:the )?shield|shields? (?:are|is) reduced"),
    ("qss", r"remove all crowd control|cleanse|quicksilver"),
    ("anticrit", r"less damage from critical|critical strikes? .{0,40}reduc|reduc\w* damage taken from critical"),
    ("antias", r"attack speed .{0,30}(?:reduc|slow)|reduc\w* .{0,30}attack speed"),
    ("truedamage", r"true damage"),
    ("shield", r"gain (?:a )?.{0,40}shield"),
    ("slow", r"slow"),
    ("magicshield", r"magic shield|magic damage shield|lifeline"),
    ("allyheal", r"heal (?:an )?all(?:y|ies)|allies .{0,30}heal|restore .{0,30}allies"),
    ("allyshield", r"shield .{0,20}all(?:y|ies)|allies .{0,30}shield"),
]


def build_items(item_en, item_tr):
    out = {}
    for k, v in item_en["data"].items():
        iid = int(k)
        if not v["gold"].get("purchasable") or v.get("requiredChampion") or v.get("requiredAlly"):
            continue
        maps = sorted(int(m) for m, on in v.get("maps", {}).items() if on and int(m) in (11, 12, 30))
        if not maps:
            continue
        desc = strip_tags(v.get("description", ""))
        stats = {}
        for sk, sv in (v.get("stats") or {}).items():
            if sk in STAT_MAP and sv:
                val = sv * 100 if sk in ("PercentAttackSpeedMod", "FlatCritChanceMod", "PercentLifeStealMod", "PercentMovementSpeedMod") else sv
                stats[STAT_MAP[sk]] = round(val, 1)
        m = re.search(r"(\d+)\s*Ability Haste", desc)
        if m:
            stats["ah"] = int(m.group(1))
        m = re.search(r"(\d+)\s*Lethality", desc)
        if m:
            stats["lethality"] = int(m.group(1))
        low = desc.lower()
        flags = sorted({f for f, pat in FLAG_PATTERNS if re.search(pat, low)})
        tr = item_tr["data"].get(k, {})
        is_boots = "Boots" in v.get("tags", [])
        total = v["gold"]["total"]
        legendary = (not v.get("into") and total >= 2000 and not is_boots and iid < 10000) or (iid >= 220000 and total >= 2000)
        out[iid] = {
            "id": iid,
            "name": v["name"],
            "nameTR": tr.get("name", v["name"]),
            "gold": total,
            "tags": v.get("tags", []),
            "stats": stats,
            "flags": flags,
            "maps": maps,
            "from": [int(x) for x in v.get("from", [])],
            "legendary": legendary,
            "boots": is_boots and total > 300,
            "starter": total <= 500 and not v.get("from"),
        }
    return out


def resolve_item(name, by_name, maps_needed):
    cands = by_name.get(name.lower(), [])
    for it in cands:
        if set(maps_needed) & set(it["maps"]):
            # prefer the base SR id (< 10000) when duplicates exist
            return it
    return None


# ----------------------------------------------------------------------------- runes

def build_runes(runes_en, runes_tr):
    tr_by_id = {}
    for st in runes_tr:
        tr_by_id[st["id"]] = st["name"]
        for slot in st["slots"]:
            for r in slot["runes"]:
                tr_by_id[r["id"]] = r["name"]
    styles = []
    for st in runes_en:
        styles.append({
            "id": st["id"], "key": st["key"], "name": st["name"], "nameTR": tr_by_id.get(st["id"], st["name"]),
            "icon": st["icon"],
            "slots": [[{"id": r["id"], "key": r["key"], "name": r["name"], "nameTR": tr_by_id.get(r["id"], r["name"]),
                        "icon": r["icon"]} for r in slot["runes"]] for slot in st["slots"]],
        })
    shards = [{"id": i, "name": n, "nameTR": t} for i, (n, t) in SHARDS.items()]
    return {"styles": styles, "shards": shards, "shardRows": SHARD_ROWS}


def rune_index(runes):
    idx = {}
    for st in runes["styles"]:
        for row, slot in enumerate(st["slots"]):
            for r in slot:
                idx[r["id"]] = (st["id"], row)
    return idx


def valid_page(page, ridx):
    perks = page["perkIds"]
    if len(perks) != 9:
        return False
    prim, sub = page["primaryStyleId"], page["subStyleId"]
    if prim == sub:
        return False
    rows = []
    for p in perks[:4]:
        if ridx.get(p, (None,))[0] != prim:
            return False
        rows.append(ridx[p][1])
    if sorted(rows) != [0, 1, 2, 3]:
        return False
    sub_rows = []
    for p in perks[4:6]:
        if ridx.get(p, (None,))[0] != sub:
            return False
        sub_rows.append(ridx[p][1])
    if 0 in sub_rows or len(set(sub_rows)) != 2:
        return False
    for i, p in enumerate(perks[6:]):
        if p not in SHARD_ROWS[i]:
            return False
    return True


RESOLVE = 8400
INSPIRATION = 8300
DEFENSIVE_SECONDARY = {RESOLVE: [8444, 8473], INSPIRATION: [8347, 8304]}  # Second Wind+Bone Plating / Cosmic Insight+Magical Footwear


def defensive_variant(page, ridx):
    sub = INSPIRATION if page["primaryStyleId"] == RESOLVE else RESOLVE
    new = dict(page)
    new["subStyleId"] = sub
    new["perkIds"] = page["perkIds"][:4] + DEFENSIVE_SECONDARY[sub] + [page["perkIds"][6], page["perkIds"][7], 5011]
    new["tag"] = "defensive"
    new["source"] = "galio"
    return new if valid_page(new, ridx) else None


# ----------------------------------------------------------------------------- augments

AFFINITY_PATTERNS = [
    ("ad", r"scalead|attack damage|physicaldamage"),
    ("ap", r"scaleap|ability power|magicdamage"),
    ("as", r"attack speed"),
    ("crit", r"critical|crit"),
    ("onhit", r"on-hit|onhit"),
    ("ah", r"ability haste|cooldown"),
    ("tank", r"scalehealth|max(?:imum)? health|bonus health|armor|magic resist|resist"),
    ("shield", r"shield"),
    ("heal", r"heal|omnivamp|life steal|lifesteal"),
    ("ms", r"move(?:ment)? speed|dash|blink"),
    ("ally", r"\bally\b|allies|teammate"),
    ("summoner", r"summoner spell"),
    ("ult", r"ultimate"),
    ("melee", r"\bmelee\b"),
    ("ranged", r"\branged\b"),
]


def augment_desc(st, name_id, mode, arena_desc):
    base = name_id.lower()
    for pre in ("aram_", "cherry_", "kiwi_"):
        if base.startswith(pre):
            base = base[len(pre):]
    keys = [f"kiwi_{base}_tooltip", f"kiwi_{base}_summary", f"kiwi_augment_{base}_tooltip",
            f"kiwi_augment_{base}_description", f"kiwi_aram_{base}_tooltip", f"kiwi_aram_{base}",
            f"augment_{base}_tooltip", f"augment_{base}_summary", f"augment_{base}_desc",
            f"cherry_{base}_summary", f"cherry_{base}_tooltip", f"{name_id.lower()}_tooltip"]
    if mode == "CHERRY":
        keys = keys[9:] + keys[:9]
        if name_id in arena_desc:
            return arena_desc[name_id]
    for k in keys:
        if k in st:
            return st[k]
    return arena_desc.get(name_id, "")


def build_augments(cherry_en, cherry_tr, lists, stringtable, arena_desc):
    tr = {a["id"]: a["nameTRA"] for a in cherry_tr}
    by_name_id = {a["augmentNameId"]: a for a in cherry_en}
    out = {}
    for lst in lists:
        mode = lst["modeName"]
        family = "ARENA" if mode == "CHERRY" else "MAYHEM"
        items = out.setdefault(family, {})
        for path in lst["augmentList"]:
            nid = path.split("/")[-1]
            a = by_name_id.get(nid)
            if not a or a["id"] in items:
                continue
            desc_raw = augment_desc(stringtable, nid, mode, arena_desc)
            desc = strip_tags(re.sub(r"%i:[a-zA-Z]+%", "", desc_raw))
            low = (desc_raw + " " + a["nameTRA"]).lower()
            aff = sorted({k for k, pat in AFFINITY_PATTERNS if re.search(pat, low)})
            items[a["id"]] = {
                "id": a["id"],
                "apiName": nid,
                "name": a["nameTRA"],
                "nameTR": tr.get(a["id"], a["nameTRA"]),
                "rarity": a["rarity"].removeprefix("k").lower(),
                "tags": [t.removeprefix("k").lower() for t in a.get("augmentDisplayTags", [])],
                "affinity": aff,
                "desc": re.sub(r"@[^@]+@", "#", desc)[:280],
                "icon": a.get("augmentLargeIconPath", "").replace("/lol-game-data/assets/", "").lower(),
            }
    return {fam: sorted(v.values(), key=lambda x: x["name"]) for fam, v in out.items()}


# ----------------------------------------------------------------------------- main build

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch")
    ap.add_argument("--bundle", action="store_true")
    args = ap.parse_args()

    versions = fetch_json(f"{DD}/api/versions.json", "versions.json", max_age=3600)
    patch = args.patch or versions[0]
    log("patch", patch)
    p = patch

    champ_en = fetch_json(f"{DD}/cdn/{p}/data/en_US/champion.json", f"{p}-champion-en.json")
    champ_tr = fetch_json(f"{DD}/cdn/{p}/data/tr_TR/champion.json", f"{p}-champion-tr.json")
    item_en = fetch_json(f"{DD}/cdn/{p}/data/en_US/item.json", f"{p}-item-en.json")
    item_tr = fetch_json(f"{DD}/cdn/{p}/data/tr_TR/item.json", f"{p}-item-tr.json")
    runes_en = fetch_json(f"{DD}/cdn/{p}/data/en_US/runesReforged.json", f"{p}-runes-en.json")
    runes_tr = fetch_json(f"{DD}/cdn/{p}/data/tr_TR/runesReforged.json", f"{p}-runes-tr.json")
    summ_en = fetch_json(f"{DD}/cdn/{p}/data/en_US/summoner.json", f"{p}-summoner-en.json")
    summ_tr = fetch_json(f"{DD}/cdn/{p}/data/tr_TR/summoner.json", f"{p}-summoner-tr.json")
    rune_recs = fetch_json(f"{CDG}/default/v1/champion-rune-recommendations.json", "rune-recs.json")
    cherry_en = fetch_json(f"{CDG}/default/v1/cherry-augments.json", "cherry-en.json")
    cherry_tr = fetch_json(f"{CDG}/tr_tr/v1/cherry-augments.json", "cherry-tr.json")
    aug_lists = fetch_json(f"{CDG}/default/v1/augment-lists.json", "augment-lists.json")
    stringtable = fetch_json(f"{CD}/game/en_us/data/menu/en_us/lol.stringtable.json", "lol.stringtable.json", max_age=7 * 86400)
    stringtable = stringtable.get("entries", stringtable)
    arena = fetch_json(f"{CD}/cdragon/arena/en_us.json", "arena-en.json")
    arena_desc = {a["apiName"]: a.get("desc", "") for a in arena.get("augments", [])}

    curated = load_curated_champions()
    arche = json.loads((CURATED / "archetypes.json").read_text(encoding="utf-8"))
    aggregates_path = ROOT / "data" / p / "aggregates.json"
    aggregates = json.loads(aggregates_path.read_text()) if aggregates_path.exists() else {}

    runes = build_runes(runes_en, runes_tr)
    ridx = rune_index(runes)
    items = build_items(item_en, item_tr)
    by_name = {}
    for it in sorted(items.values(), key=lambda x: x["id"]):
        by_name.setdefault(it["name"].lower(), []).append(it)

    summoners = []
    tr_s = {v["key"]: v["name"] for v in summ_tr["data"].values()}
    for v in summ_en["data"].values():
        summoners.append({"id": int(v["key"]), "ddId": v["id"], "name": v["name"], "nameTR": tr_s.get(v["key"], v["name"]),
                          "modes": v.get("modes", []), "image": v["image"]["full"]})
    summoners.sort(key=lambda s: s["id"])

    recs_by_id = {r["championId"]: r["runeRecommendations"] for r in rune_recs}
    warnings = []

    def resolve_names(names, maps_needed, cid, what):
        res = []
        for n in names:
            it = resolve_item(n, by_name, maps_needed)
            if it:
                if it["id"] not in res:
                    res.append(it["id"])
            else:
                warnings.append(f"{cid}: {what} item '{n}' not on maps {maps_needed}")
        return res

    index = []
    details = {}
    for cid, dd in sorted(champ_en["data"].items()):
        key = int(dd["key"])
        cd = fetch_json(f"{CDG}/default/v1/champions/{key}.json", f"cd-champ-{key}.json", max_age=7 * 86400)
        cur = curated.get(cid)
        if not cur:
            warnings.append(f"{cid}: no curated entry, using heuristics")
            cur = {"skill": ["Q", "E", "W"], "archetype": heuristic_archetype(cd), "archetypes": {}, "attrs": {}}
        attrs = derive_attrs(cd, dd, cur)
        recs = recs_by_id.get(key, [])
        positions = []
        for r in sorted(recs, key=lambda r: not r["isDefaultPosition"]):
            if r["mapId"] == 11 and r["position"] in POSITIONS and r["position"] not in positions:
                positions.append(r["position"])
        if not positions:
            positions = ["MIDDLE"]

        agg = aggregates.get(cid, {})
        skill = agg.get("skillMax") or cur["skill"]
        builds = {}
        for pos in positions + ["ARAM"]:
            map_id = 12 if pos == "ARAM" else 11
            arch = cur["archetypes"].get(pos, cur["archetype"]) if pos != "ARAM" else cur["archetype"]
            if pos == "UTILITY" and arch not in ("enchanter", "catcher", "artillery", "battlemage", "burstmage", "tank"):
                arch = "catcher"
            tmpl = arche["archetypes"][arch]
            pages = []
            spells = []
            for r in recs:
                if r["mapId"] != map_id or (map_id == 11 and r["position"] != pos):
                    continue
                page = {"primaryStyleId": r["primaryPerkStyleId"], "subStyleId": r["secondaryPerkStyleId"],
                        "perkIds": r["perkIds"], "source": "riot", "tag": "standard" if not pages else "alternative"}
                if valid_page(page, ridx) and page["perkIds"] not in [x["perkIds"] for x in pages]:
                    pages.append(page)
                sp = r.get("summonerSpellIds") or []
                if len(sp) == 2 and sp not in spells:
                    spells.append(sp)
            if pages:
                dv = defensive_variant(pages[0], ridx)
                if dv and dv["perkIds"] not in [x["perkIds"] for x in pages]:
                    pages.append(dv)
            else:
                warnings.append(f"{cid}/{pos}: no valid rune recommendation")
            maps_needed = [map_id]
            core_names = arche["championOverrides"].get(cid, {}).get("core", tmpl["core"])
            core = resolve_names(core_names, maps_needed, cid, "core")
            if agg.get("core", {}).get(pos):
                core = agg["core"][pos] + [c for c in core if c not in agg["core"][pos]]
            if pos == "JUNGLE":
                jkind = "tank" if arch in ("tank", "tankmage") else ("ap" if damage_type(cd) == "magic" else "ad")
                starter_names = arche["jungleStarter"][jkind]
            else:
                starter_names = tmpl["starter"]
            starter = resolve_names(starter_names, maps_needed, cid, "starter") if pos != "ARAM" else []
            boots = resolve_names(tmpl["boots"], maps_needed, cid, "boots")
            situational = []
            for name, cond in tmpl["situational"]:
                it = resolve_item(name, by_name, maps_needed)
                if not it:
                    warnings.append(f"{cid}: situational '{name}' missing")
                    continue
                existing = next((s for s in situational if s["id"] == it["id"]), None)
                if existing:
                    existing["when"].append(cond)
                else:
                    situational.append({"id": it["id"], "when": [cond]})
            builds[pos] = {
                "archetype": arch,
                "itemClass": tmpl["class"],
                "runes": pages[:3],
                "spells": spells[:3],
                "items": {"starter": starter, "boots": boots, "core": core, "situational": situational},
            }
        title_tr = champ_tr["data"].get(cid, {}).get("title", dd["title"])
        entry = {
            "id": cid, "key": key, "name": dd["name"], "nameTR": champ_tr["data"].get(cid, {}).get("name", dd["name"]),
            "title": dd["title"], "titleTR": title_tr,
            "tags": dd["tags"], "roles": cd.get("roles", []), "positions": positions,
            "damageType": damage_type(cd), "attackType": cd.get("tacticalInfo", {}).get("attackType", "melee"),
            "range": int(dd["stats"]["attackrange"]), "difficulty": dd["info"]["difficulty"],
            "archetype": cur["archetype"], "attrs": attrs,
            "spellNames": {s["spellKey"].upper(): s["name"] for s in cd.get("spells", [])},
        }
        index.append(entry)
        details[cid] = {
            "id": cid, "key": key, "patch": patch,
            "source": "riot-recommended+curated" + ("+match-v5" if agg else ""),
            "skillOrder": {"max": skill, "first": list(skill), "ultLevels": [6, 11, 16]},
            "builds": builds,
        }

    augments = build_augments(cherry_en, cherry_tr, aug_lists, stringtable, arena_desc)

    out_dir = ROOT / "data" / patch
    (out_dir / "champions").mkdir(parents=True, exist_ok=True)
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()

    def dump(path, obj):
        path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")

    items_list = sorted(items.values(), key=lambda x: x["id"])
    dump(out_dir / "champions.json", index)
    for cid, d in details.items():
        dump(out_dir / "champions" / f"{cid}.json", d)
    dump(out_dir / "items.json", items_list)
    dump(out_dir / "runes.json", runes)
    dump(out_dir / "summoners.json", summoners)
    dump(out_dir / "augments.json", augments)
    allj = {"schema": SCHEMA, "patch": patch, "generatedAt": now, "champions": index, "details": details,
            "items": items_list, "runes": runes, "summoners": summoners, "augments": augments}
    dump(out_dir / "all.json", allj)
    manifest = {"schema": SCHEMA, "latest": patch, "generatedAt": now, "champions": len(index),
                "files": {"all": f"{patch}/all.json"}}
    (ROOT / "data" / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if args.bundle:
        b = ROOT / "Galio" / "Resources" / "BundledData"
        b.mkdir(parents=True, exist_ok=True)
        shutil.copy(out_dir / "all.json", b / "all.json")
        shutil.copy(ROOT / "data" / "manifest.json", b / "manifest.json")
    (out_dir / "build-warnings.txt").write_text("\n".join(sorted(set(warnings))) + "\n", encoding="utf-8")
    log(f"wrote {len(index)} champions, {len(items_list)} items, "
        f"{sum(len(v) for v in augments.values())} augments, {len(set(warnings))} warnings")


if __name__ == "__main__":
    main()
