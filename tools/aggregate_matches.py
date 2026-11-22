#!/usr/bin/env python3
"""Aggregate real games (Riot Match-v5 + Timeline) into anonymous per-champion counts.

Outputs (per Data Dragon patch):
  data/<patch>/aggregate_counts.json   raw anonymous counts, accumulated across runs (committed)
  data/<patch>/aggregates.json         derived recommendations with sample sizes (merged by build_data.py)
  tools/.cache/processed_matches.json  match IDs already counted (gitignored, never published)

Counts per champion -> position (TOP/JUNGLE/MIDDLE/BOTTOM/UTILITY, or ARAM):
  games, wins, skill max orders, first three skill-ups, 3-item cores, keystone+secondary tree,
  full rune pages, summoner spell pairs, first boots (every option stores [games, wins]), and
  summed per-game stats (minutes, CS, damage to champions, vision, deaths, gold) for benchmarks.
No PUUIDs, Riot IDs or other per-player data are written anywhere; PUUIDs are only held in
memory to list match IDs.

Key: RIOT_API_KEY, or (when unset) the file ~/.hermes/secrets/riot_api_key. Never printed;
any "RGAPI-..." text is redacted from log lines.

Usage:
  python3 tools/aggregate_matches.py --budget-minutes 45
  python3 tools/aggregate_matches.py --derive-only      # rebuild aggregates.json from the counts
Rate limits are read from X-App-Rate-Limit response headers per host (each routing value has its
own budget), Retry-After is honoured, and the regional clusters (europe, asia, americas) run in
parallel threads.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import pathlib
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
KEY_FILE = pathlib.Path("~/.hermes/secrets/riot_api_key")
LEGENDARY_MIN_GOLD = 2200
POSITIONS = ("TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY")
QUEUE_RANKED = 420
QUEUE_ARAM = 450

# Derivation thresholds (see docs/DATA.md).
MIN_POSITION_GAMES = 20      # champion/position sample before match data overrides rule data
MIN_POSITION_SHARE = 0.10    # share of the champion's SR games needed to list a position
MIN_SKILL_GAMES = 20
MIN_OPTION_GAMES = 5         # an option (core/page/spells/boots) must appear this often
MIN_CORE_SHARE = 0.05        # ...and a 3-item core set in at least 5 % of the position's games

# Platform -> regional cluster. Sampled round-robin inside each cluster.
CLUSTERS = {
    "europe": ["tr1", "euw1", "eun1"],
    "asia": ["kr"],
    "americas": ["na1"],
}
TIERS = [("CHALLENGER", None), ("GRANDMASTER", None), ("MASTER", None),
         ("DIAMOND", "I"), ("DIAMOND", "II"), ("EMERALD", "I")]

_KEY_RE = re.compile(r"RGAPI-[0-9A-Za-z-]+")


def redact(text: str) -> str:
    return _KEY_RE.sub("RGAPI-[redacted]", str(text))


def log(*a):
    print(redact(" ".join(str(x) for x in a)), file=sys.stderr, flush=True)


def load_key(env=None, key_file: pathlib.Path | None = None) -> str:
    env = os.environ if env is None else env
    key = (env.get("RIOT_API_KEY") or "").strip()
    if key:
        return key
    path = (key_file or KEY_FILE).expanduser()
    try:
        return path.read_text().strip()
    except OSError:
        return ""


# ----------------------------------------------------------------------------- HTTP + rate limit

class HostLimiter:
    """Sliding-window limiter for one host, configured from the rate-limit headers."""

    def __init__(self):
        self.windows = [(18, 1.0), (90, 120.0)]  # conservative default = development key
        self.stamps: collections.deque[float] = collections.deque()
        self.blocked_until = 0.0
        self.lock = threading.Lock()

    def configure(self, header: str | None):
        if not header:
            return
        wins = []
        for part in header.split(","):
            try:
                n, sec = part.split(":")
                wins.append((max(1, int(int(n) * 0.9)), float(sec)))  # keep a 10 % margin
            except ValueError:
                continue
        if wins:
            with self.lock:
                self.windows = wins

    def wait(self):
        while True:
            with self.lock:
                now = time.monotonic()
                delay = max(0.0, self.blocked_until - now)
                longest = max(s for _, s in self.windows)
                while self.stamps and now - self.stamps[0] > longest:
                    self.stamps.popleft()
                for n, sec in self.windows:
                    recent = [t for t in self.stamps if now - t < sec]
                    if len(recent) >= n:
                        delay = max(delay, sec - (now - recent[-n]) + 0.05)
                if delay <= 0:
                    self.stamps.append(now)
                    return
            time.sleep(min(delay, 5.0))

    def block(self, seconds: float):
        with self.lock:
            self.blocked_until = max(self.blocked_until, time.monotonic() + seconds)


class Riot:
    def __init__(self, key: str):
        self.key = key
        self.limiters: dict[str, HostLimiter] = collections.defaultdict(HostLimiter)
        self.requests = collections.Counter()
        self.key_rejected = False

    def get(self, url: str):
        host = urllib.parse.urlparse(url).netloc
        lim = self.limiters[host]
        for attempt in range(5):
            if self.key_rejected:
                return None
            lim.wait()
            self.requests[host] += 1
            req = urllib.request.Request(url, headers={"X-Riot-Token": self.key, "User-Agent": "galio-aggregator/1.1"})
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    lim.configure(r.headers.get("X-App-Rate-Limit"))
                    return json.loads(r.read())
            except urllib.error.HTTPError as e:
                lim.configure(e.headers.get("X-App-Rate-Limit"))
                if e.code == 429:
                    wait = float(e.headers.get("Retry-After") or 10)
                    log(f"429 on {host} ({e.headers.get('X-Rate-Limit-Type', '?')}), waiting {wait:.0f}s")
                    lim.block(wait)
                    continue
                if e.code in (500, 502, 503, 504):
                    time.sleep(2 * (attempt + 1))
                    continue
                if e.code == 401 or (e.code == 403 and "/match/" in url):
                    log(f"HTTP {e.code} on {host}: key rejected")
                    self.key_rejected = True
                    return None
                if e.code != 404:
                    log(f"HTTP {e.code} on {host}{urllib.parse.urlparse(url).path.split('/by-puuid/')[0]}")
                return None
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                log(f"network error on {host}: {e}; retrying")
                time.sleep(2 * (attempt + 1))
        return None


# ----------------------------------------------------------------------------- counting

def skill_max_order(levelups: list[int]) -> list[str] | None:
    """levelups: skillSlot per SKILL_LEVEL_UP event (1=Q 2=W 3=E 4=R). Max order = order in which
    each basic ability reaches rank 5 (fallback: rank at level 11)."""
    keys = {1: "Q", 2: "W", 3: "E"}
    ranks = collections.Counter()
    maxed: list[str] = []
    for slot in levelups:
        if slot not in keys:
            continue
        ranks[slot] += 1
        if ranks[slot] == 5:
            maxed.append(keys[slot])
    if len(maxed) < 2:
        snapshot = collections.Counter(s for s in levelups[:11] if s in keys)
        if not snapshot:
            return None
        maxed = [keys[s] for s, _ in snapshot.most_common()]
    for k in "QWE":
        if k not in maxed:
            maxed.append(k)
    return maxed[:3]


def _bump(table: dict, key: str, win: bool):
    cell = table.setdefault(key, [0, 0])
    cell[0] += 1
    cell[1] += int(win)


def new_counts(patch: str) -> dict:
    return {"schema": 2, "patch": patch, "matches": 0, "byPlatform": {}, "byQueue": {}, "champions": {}}


def participant_events(timeline: dict, items: dict):
    """Per participant: normal skill-ups, completed legendary items (in order), first tier-2 boots."""
    levelups = collections.defaultdict(list)
    bought = collections.defaultdict(list)
    for frame in timeline.get("info", {}).get("frames", []):
        for ev in frame.get("events", []):
            t = ev.get("type")
            pid = ev.get("participantId")
            if t == "SKILL_LEVEL_UP" and ev.get("levelUpType") == "NORMAL":
                levelups[pid].append(ev.get("skillSlot"))
            elif t == "ITEM_PURCHASED":
                bought[pid].append(ev.get("itemId"))
            elif t == "ITEM_UNDO":
                before = ev.get("beforeId")
                lst = bought[pid]
                if before in lst:
                    del lst[len(lst) - 1 - lst[::-1].index(before)]
    cores, boots = {}, {}
    for pid, lst in bought.items():
        core = []
        for iid in lst:
            it = items.get(iid)
            if not it:
                continue
            if it.get("boots"):
                boots.setdefault(pid, iid)
            elif it.get("legendary") and it.get("gold", 0) >= LEGENDARY_MIN_GOLD and iid not in core:
                core.append(iid)
        cores[pid] = core
    return levelups, cores, boots


def add_match(counts: dict, processed: set, match_id: str, match: dict, timeline: dict,
              items: dict, champ_by_key: dict, platform: str = "") -> bool:
    """Count one match. Returns False (and counts nothing) if it was already processed or unusable."""
    if match_id in processed:
        return False
    info = (match or {}).get("info", {})
    queue = info.get("queueId")
    if queue not in (QUEUE_RANKED, QUEUE_ARAM) or info.get("gameDuration", 0) < 300:
        return False
    participants = info.get("participants", [])
    if any(p.get("gameEndedInEarlySurrender") for p in participants):
        return False
    levelups, cores, boots = participant_events(timeline or {}, items)
    for p in participants:
        cid = champ_by_key.get(p.get("championId"))
        pos = "ARAM" if queue == QUEUE_ARAM else (p.get("teamPosition") or "")
        if not cid or (pos != "ARAM" and pos not in POSITIONS):
            continue
        win = bool(p.get("win"))
        pid = p.get("participantId")
        c = counts["champions"].setdefault(cid, {}).setdefault(pos, {
            "games": 0, "wins": 0, "skillMax": {}, "skillStart": {}, "core": {}, "runeTrees": {},
            "runePages": {}, "spells": {}, "boots": {}})
        c["games"] += 1
        c["wins"] += int(win)
        st = c.setdefault("stats", {"games": 0, "minutes": 0.0, "cs": 0, "damage": 0, "vision": 0, "deaths": 0, "gold": 0})
        st["games"] += 1
        st["minutes"] = round(st["minutes"] + info.get("gameDuration", 0) / 60, 2)
        st["cs"] += int(p.get("totalMinionsKilled", 0)) + int(p.get("neutralMinionsKilled", 0))
        st["damage"] += int(p.get("totalDamageDealtToChampions", 0))
        st["vision"] += int(p.get("visionScore", 0))
        st["deaths"] += int(p.get("deaths", 0))
        st["gold"] += int(p.get("goldEarned", 0))
        ups = levelups.get(pid, [])
        order = skill_max_order(ups)
        if order:
            _bump(c["skillMax"], "".join(order), win)
        start = "".join({1: "Q", 2: "W", 3: "E"}.get(s, "?") for s in ups[:3])
        if len(start) == 3 and "?" not in start:
            _bump(c["skillStart"], start, win)
        core = cores.get(pid, [])
        if len(core) >= 3:
            _bump(c["core"], "-".join(str(i) for i in core[:3]), win)
        perks_obj = p.get("perks") or {}
        styles = perks_obj.get("styles") or []
        stat = perks_obj.get("statPerks") or {}
        if len(styles) == 2 and styles[0].get("selections"):
            prim, sub = styles[0], styles[1]
            keystone = prim["selections"][0]["perk"]
            _bump(c["runeTrees"], f"{keystone}:{sub.get('style')}", win)
            perks = [s["perk"] for s in prim["selections"]] + [s["perk"] for s in sub.get("selections", [])]
            shards = [stat.get("offense"), stat.get("flex"), stat.get("defense")]
            if len(perks) == 6 and all(shards):
                _bump(c["runePages"], f"{prim.get('style')}:{sub.get('style')}:" + ",".join(str(x) for x in perks + shards), win)
        s1, s2 = p.get("summoner1Id"), p.get("summoner2Id")
        if s1 and s2:
            _bump(c["spells"], "-".join(str(x) for x in sorted((s1, s2))), win)
        if pid in boots:
            _bump(c["boots"], str(boots[pid]), win)
    processed.add(match_id)
    counts["matches"] += 1
    if platform:
        counts["byPlatform"][platform] = counts["byPlatform"].get(platform, 0) + 1
    counts["byQueue"][str(queue)] = counts["byQueue"].get(str(queue), 0) + 1
    return True


# ----------------------------------------------------------------------------- derivation

def _rank(options: dict, min_games: int = MIN_OPTION_GAMES):
    """Popular options first; among options with at least half the top count, a smoothed win
    rate (internal only, never published) breaks near-ties. Returns [(key, games)]."""
    opts = [(k, g, w) for k, (g, w) in options.items() if g >= min_games]
    if not opts:
        return []
    top = max(g for _, g, _ in opts)

    def score(o):
        _, g, w = o
        contender = g >= top / 2
        smoothed = (w + 10) / (g + 20)  # pulled toward 50 % with 20 virtual games
        return (contender, smoothed if contender else 0.0, g)

    return [(k, g) for k, g, _ in sorted(opts, key=score, reverse=True)]


def derive(counts: dict) -> dict:
    """Recommendations with sample sizes. Positions below the thresholds are omitted, so the
    rule-based data stays in charge there. No win rates are written."""
    out = {"_meta": {"patch": counts.get("patch"), "matches": counts.get("matches", 0),
                     "byPlatform": counts.get("byPlatform", {}), "byQueue": counts.get("byQueue", {}),
                     "thresholds": {"positionGames": MIN_POSITION_GAMES, "positionShare": MIN_POSITION_SHARE,
                                    "optionGames": MIN_OPTION_GAMES, "skillGames": MIN_SKILL_GAMES}}}
    for cid, by_pos in sorted(counts.get("champions", {}).items()):
        sr_total = sum(v["games"] for k, v in by_pos.items() if k != "ARAM")
        entry: dict = {"games": sr_total, "positions": {}}
        skill_all: dict = {}
        for pos, c in by_pos.items():
            if pos != "ARAM":
                for k, (g, w) in c["skillMax"].items():
                    cell = skill_all.setdefault(k, [0, 0])
                    cell[0] += g
                    cell[1] += w
            share = c["games"] / sr_total if pos != "ARAM" and sr_total else 1.0
            if c["games"] < MIN_POSITION_GAMES or share < MIN_POSITION_SHARE:
                continue
            d: dict = {"games": c["games"], "share": round(share, 3)}
            st = c.get("stats") or {}
            if st.get("games", 0) >= MIN_POSITION_GAMES and st.get("minutes", 0) > 0:
                m = st["minutes"]
                d["benchmarks"] = {"games": st["games"], "csPerMin": round(st["cs"] / m, 2),
                                   "damagePerMin": round(st["damage"] / m, 1), "visionPerMin": round(st["vision"] / m, 2),
                                   "goldPerMin": round(st["gold"] / m, 1), "deaths": round(st["deaths"] / st["games"], 2)}
            # Cores: pick the most popular *set* of three items, then its most common purchase order
            # (ordered triples alone fragment the sample).
            by_set: dict = {}
            for k, (g, w) in c["core"].items():
                cell = by_set.setdefault("-".join(sorted(k.split("-"))), [0, 0])
                cell[0] += g
                cell[1] += w
            core_sets = _rank(by_set, max(MIN_OPTION_GAMES, int(c["games"] * MIN_CORE_SHARE)))
            if core_sets:
                best_set = set(core_sets[0][0].split("-"))
                orders = {k: v for k, v in c["core"].items() if set(k.split("-")) == best_set}
                order = max(orders.items(), key=lambda kv: (kv[1][0], kv[0]))[0]
                d["core"] = [int(x) for x in order.split("-")]
                d["coreGames"] = core_sets[0][1]
            pages = _rank(c["runePages"])
            if pages:
                prim, sub, perks = pages[0][0].split(":")
                d["runePage"] = {"primaryStyleId": int(prim), "subStyleId": int(sub),
                                 "perkIds": [int(x) for x in perks.split(",")], "games": pages[0][1]}
            trees = _rank(c["runeTrees"])
            if trees:
                ks, sub = trees[0][0].split(":")
                d["runeTree"] = {"keystone": int(ks), "subStyleId": int(sub), "games": trees[0][1]}
            spells = _rank(c["spells"])
            if spells:
                d["spells"] = [int(x) for x in spells[0][0].split("-")]
                d["spellsGames"] = spells[0][1]
            boots = _rank(c["boots"])
            if boots:
                d["boots"] = int(boots[0][0])
                d["bootsGames"] = boots[0][1]
            sk = _rank(c["skillMax"], MIN_SKILL_GAMES)
            if sk:
                d["skillMax"] = list(sk[0][0])
            unlock: dict = {}  # raw first three skill-ups (e.g. QWQ) -> unlock order of the basics (QWE)
            for k, (g, w) in c["skillStart"].items():
                order = "".join(dict.fromkeys(k)) + "".join(x for x in "QWE" if x not in k)
                cell = unlock.setdefault(order, [0, 0])
                cell[0] += g
                cell[1] += w
            st = _rank(unlock)
            if st:
                d["skillStart"] = list(st[0][0])
            entry["positions"][pos] = d
        sk = _rank(skill_all, MIN_SKILL_GAMES)
        if sk:
            entry["skillMax"] = list(sk[0][0])
            entry["skillGames"] = sk[0][1]
        if entry["positions"] or "skillMax" in entry:
            out[cid] = entry
    return out


# ----------------------------------------------------------------------------- persistence

def load_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def atomic_write(path: pathlib.Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


class Store:
    def __init__(self, patch: str, data_dir: pathlib.Path = ROOT / "data", cache_dir: pathlib.Path = CACHE):
        self.patch = patch
        self.counts_path = data_dir / patch / "aggregate_counts.json"
        self.agg_path = data_dir / patch / "aggregates.json"
        self.ids_path = cache_dir / "processed_matches.json"
        self.counts = load_json(self.counts_path, None) or new_counts(patch)
        if self.counts.get("schema") != 2 or self.counts.get("patch") != patch:
            self.counts = new_counts(patch)
        ids = load_json(self.ids_path, {})
        self.processed: set[str] = set(ids.get(patch, [])) if isinstance(ids, dict) else set()
        self.lock = threading.RLock()

    def save(self):
        with self.lock:
            ids = load_json(self.ids_path, {})
            if not isinstance(ids, dict):
                ids = {}
            ids[self.patch] = sorted(self.processed)
            # IDs first: a crash in between can only lose counts, never double count on the next run.
            atomic_write(self.ids_path, json.dumps(ids))
            atomic_write(self.counts_path, json.dumps(self.counts, sort_keys=True, separators=(",", ":")) + "\n")

    def write_aggregates(self):
        with self.lock:
            atomic_write(self.agg_path, json.dumps(derive(self.counts), indent=1, sort_keys=True) + "\n")


# ----------------------------------------------------------------------------- sampling

def player_puuids(riot: Riot, platform: str, per_tier: int):
    plat = f"https://{platform}.api.riotgames.com"
    for tier, div in TIERS:
        if div is None:
            league = riot.get(f"{plat}/lol/league/v4/{tier.lower()}leagues/by-queue/RANKED_SOLO_5x5") or {}
            entries = sorted(league.get("entries", []), key=lambda e: -e.get("leaguePoints", 0))
        else:
            entries = riot.get(f"{plat}/lol/league-exp/v4/entries/RANKED_SOLO_5x5/{tier}/{div}?page=1") or []
        got = [e["puuid"] for e in entries if e.get("puuid")]
        random.shuffle(got)  # a different slice of each tier on every run (repeat runs find new matches)
        got = got[:per_tier]
        log(f"{platform} {tier} {div or ''}: {len(got)} players")
        yield from got


def _version_tuple(v: str) -> tuple:
    parts = []
    for x in v.split(".")[:2]:
        try:
            parts.append(int(x))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def run_cluster(riot: Riot, store: Store, region: str, platforms: list[str], deadline: float,
                items: dict, champ_by_key: dict, major_minor: str, args, stats: dict):
    reg = f"https://{region}.api.riotgames.com"
    since = int(time.time()) - args.days * 86400
    gens = {pl: player_puuids(riot, pl, args.players_per_tier) for pl in platforms}
    active = list(platforms)
    other_patch = 0
    while active and time.monotonic() < deadline and not riot.key_rejected:
        for pl in list(active):
            if time.monotonic() >= deadline:
                break
            puuid = next(gens[pl], None)
            if puuid is None:
                active.remove(pl)
                continue
            lists = []
            for queue, n in ((QUEUE_RANKED, args.matches), (QUEUE_ARAM, args.aram_matches)):
                if n > 0:
                    q = urllib.parse.urlencode({"queue": queue, "count": n, "startTime": since})
                    lists.append(riot.get(f"{reg}/lol/match/v5/matches/by-puuid/{puuid}/ids?{q}") or [])
            puuid = None  # identities are not kept beyond this point
            for ids in lists:  # each list is newest first
                for mid in ids:
                    if time.monotonic() >= deadline:
                        break
                    with store.lock:
                        if mid in store.processed:
                            continue
                    match = riot.get(f"{reg}/lol/match/v5/matches/{mid}")
                    if not match:
                        continue
                    info = match.get("info", {})
                    if not info.get("gameVersion", "").startswith(major_minor + "."):
                        with store.lock:
                            store.processed.add(mid)  # other patch: never fetch it again
                        other_patch += 1
                        if _version_tuple(info.get("gameVersion", "")) < _version_tuple(major_minor):
                            # Older patch: the rest of this list is older too, and later listings
                            # only need matches created after this one.
                            since = max(since, int(info.get("gameCreation", 0)) // 1000 + 1)
                            break
                        continue
                    timeline = riot.get(f"{reg}/lol/match/v5/matches/{mid}/timeline")
                    if not timeline:
                        continue
                    with store.lock:
                        ok = add_match(store.counts, store.processed, mid, match, timeline, items, champ_by_key, pl)
                        if not ok:
                            store.processed.add(mid)
                        else:
                            stats[pl] = stats.get(pl, 0) + 1
                            if sum(stats.values()) % 25 == 0:
                                store.save()
                                log(f"progress: new {dict(stats)}, total {store.counts['matches']}")
    log(f"{region} done ({other_patch} matches from other patches skipped)")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--clusters", default="europe,asia,americas")
    ap.add_argument("--players-per-tier", type=int, default=40)
    ap.add_argument("--matches", type=int, default=12, help="ranked matches listed per player")
    ap.add_argument("--aram-matches", type=int, default=4, help="ARAM matches listed per player")
    ap.add_argument("--days", type=int, default=14, help="only list matches from the last N days")
    ap.add_argument("--budget-minutes", type=float, default=30)
    ap.add_argument("--patch", help="Data Dragon patch, default = data/manifest.json latest")
    ap.add_argument("--derive-only", action="store_true")
    args = ap.parse_args(argv)

    manifest = json.loads((ROOT / "data" / "manifest.json").read_text())
    patch = args.patch or manifest["latest"]
    major_minor = ".".join(patch.split(".")[:2])
    store = Store(patch)
    if args.derive_only:
        store.write_aggregates()
        log(f"derived {store.agg_path} from {store.counts['matches']} matches")
        return 0

    key = load_key()
    if not key:
        log("No Riot API key (RIOT_API_KEY or ~/.hermes/secrets/riot_api_key): skipping Match-v5 aggregation.")
        return 0
    allj = json.loads((ROOT / "data" / patch / "all.json").read_text())
    items = {i["id"]: i for i in allj["items"]}
    champ_by_key = {c["key"]: c["id"] for c in allj["champions"]}
    riot = Riot(key)
    deadline = time.monotonic() + args.budget_minutes * 60
    stats: dict[str, int] = {}
    log(f"patch {major_minor}: {store.counts['matches']} matches already counted, budget {args.budget_minutes} min")
    threads = []
    for region in args.clusters.split(","):
        t = threading.Thread(target=run_cluster, daemon=True,
                             args=(riot, store, region, CLUSTERS[region], deadline, items, champ_by_key,
                                   major_minor, args, stats))
        t.start()
        threads.append(t)
    try:
        for t in threads:
            t.join(max(1.0, deadline - time.monotonic() + 90))
    except KeyboardInterrupt:
        log("interrupted; saving")
    store.save()
    store.write_aggregates()
    log(f"new matches this run: {dict(stats)}; total {store.counts['matches']} {store.counts['byPlatform']}; "
        f"requests {dict(riot.requests)}")
    if riot.key_rejected:
        log("key was rejected during the run; partial counts were saved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
