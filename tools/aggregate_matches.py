#!/usr/bin/env python3
"""Aggregate real ranked games (Riot Match-v5 + Timeline) into per-champion skill orders and item cores.

Activated only when RIOT_API_KEY is set (never commit the key; export it in the shell or a
local, untracked .env). Output: data/<patch>/aggregates.json, which tools/build_data.py merges.

What is stored: anonymous counts per champion/position (most common skill max order and first
three completed items). No PUUIDs, names or per-player data are written anywhere.

Usage:
  RIOT_API_KEY=... python3 tools/aggregate_matches.py --platform tr1 --region europe --players 60 --matches 15
Rate limits: a personal/development key allows 20 req/s and 100 req/2 min; the script sleeps
1.25 s between calls by default (--delay). A production key can lower --delay.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEGENDARY_MIN_GOLD = 2200


def log(*a):
    print(*a, file=sys.stderr)


class Riot:
    def __init__(self, key: str, delay: float):
        self.key = key
        self.delay = delay

    def get(self, url: str):
        for attempt in range(5):
            time.sleep(self.delay)
            req = urllib.request.Request(url, headers={"X-Riot-Token": self.key, "User-Agent": "galio-aggregator/1.0"})
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    return json.loads(r.read())
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    wait = int(e.headers.get("Retry-After", "10"))
                    log(f"rate limited, sleeping {wait}s")
                    time.sleep(wait)
                    continue
                if e.code in (500, 502, 503, 504):
                    time.sleep(2 * (attempt + 1))
                    continue
                if e.code in (401, 403):
                    raise SystemExit("RIOT_API_KEY rejected (expired or missing permissions)")
                log(f"HTTP {e.code} for {url}")
                return None
            except urllib.error.URLError as e:
                log(f"network error {e}; retrying")
                time.sleep(2)
        return None


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", default="tr1")
    ap.add_argument("--region", default="europe")
    ap.add_argument("--queue", type=int, default=420)
    ap.add_argument("--players", type=int, default=60)
    ap.add_argument("--matches", type=int, default=15, help="matches per player")
    ap.add_argument("--delay", type=float, default=1.25)
    ap.add_argument("--patch", help="Data Dragon patch, default = data/manifest.json latest")
    args = ap.parse_args()

    key = os.environ.get("RIOT_API_KEY", "").strip()
    if not key:
        log("RIOT_API_KEY not set: skipping Match-v5 aggregation (static + curated data is used).")
        return 0
    manifest = json.loads((ROOT / "data" / "manifest.json").read_text())
    patch = args.patch or manifest["latest"]
    major_minor = ".".join(patch.split(".")[:2])
    allj = json.loads((ROOT / "data" / patch / "all.json").read_text())
    items = {i["id"]: i for i in allj["items"]}
    champ_by_key = {c["key"]: c["id"] for c in allj["champions"]}

    riot = Riot(key, args.delay)
    plat = f"https://{args.platform}.api.riotgames.com"
    reg = f"https://{args.region}.api.riotgames.com"

    puuids: list[str] = []
    for tier in ("challengerleagues", "grandmasterleagues", "masterleagues"):
        league = riot.get(f"{plat}/lol/league/v4/{tier}/by-queue/RANKED_SOLO_5x5") or {}
        for e in sorted(league.get("entries", []), key=lambda e: -e.get("leaguePoints", 0)):
            if e.get("puuid"):
                puuids.append(e["puuid"])
        if len(puuids) >= args.players:
            break
    puuids = puuids[: args.players]
    log(f"{len(puuids)} players")

    match_ids: set[str] = set()
    for p in puuids:
        q = urllib.parse.urlencode({"queue": args.queue, "count": args.matches, "type": "ranked"})
        ids = riot.get(f"{reg}/lol/match/v5/matches/by-puuid/{p}/ids?{q}") or []
        match_ids.update(ids)
    puuids.clear()  # identities are not needed beyond this point
    log(f"{len(match_ids)} matches")

    skill_votes: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    core_votes: dict[tuple[str, str], collections.Counter] = collections.defaultdict(collections.Counter)
    used = 0
    for mid in sorted(match_ids):
        match = riot.get(f"{reg}/lol/match/v5/matches/{mid}")
        if not match or not match.get("info", {}).get("gameVersion", "").startswith(major_minor):
            continue
        timeline = riot.get(f"{reg}/lol/match/v5/matches/{mid}/timeline")
        if not timeline:
            continue
        used += 1
        part = {p["participantId"]: p for p in match["info"]["participants"]}
        levelups = collections.defaultdict(list)
        purchases = collections.defaultdict(list)
        for frame in timeline["info"]["frames"]:
            for ev in frame.get("events", []):
                if ev.get("type") == "SKILL_LEVEL_UP" and ev.get("levelUpType") == "NORMAL":
                    levelups[ev["participantId"]].append(ev["skillSlot"])
                elif ev.get("type") == "ITEM_PURCHASED":
                    it = items.get(ev["itemId"])
                    if it and it.get("legendary") and it["gold"] >= LEGENDARY_MIN_GOLD:
                        purchases[ev["participantId"]].append(ev["itemId"])
        for pid, p in part.items():
            cid = champ_by_key.get(p.get("championId"))
            pos = p.get("teamPosition") or ""
            if not cid or pos not in ("TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY"):
                continue
            order = skill_max_order(levelups.get(pid, []))
            if order:
                skill_votes[cid]["".join(order)] += 1
            core = []
            for iid in purchases.get(pid, []):
                if iid not in core:
                    core.append(iid)
            if len(core) >= 3:
                core_votes[(cid, pos)][tuple(core[:3])] += 1
    log(f"aggregated {used} matches on patch {major_minor}")

    out: dict[str, dict] = {}
    for cid, votes in skill_votes.items():
        best, n = votes.most_common(1)[0]
        if n >= 5:
            out.setdefault(cid, {})["skillMax"] = list(best)
    for (cid, pos), votes in core_votes.items():
        best, n = votes.most_common(1)[0]
        if n >= 4:
            out.setdefault(cid, {}).setdefault("core", {})[pos] = list(best)
    out_path = ROOT / "data" / patch / "aggregates.json"
    out_path.write_text(json.dumps({"_meta": {"matches": used, "patch": major_minor, "queue": args.queue}, **out},
                                   indent=1, sort_keys=True) + "\n")
    log(f"wrote {out_path} ({len(out)} champions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
