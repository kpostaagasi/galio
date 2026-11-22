# Galio recommendation data

The app never scrapes third-party stat sites (op.gg, u.gg, mobalytics… forbid it). All data comes from:

| Source | Used for |
|---|---|
| Riot **Data Dragon** (`ddragon.leagueoflegends.com`) | patch list, champions (tags, stats, TR/EN names), items (stats, recipes, maps), runes, summoner spells, icons |
| **CommunityDragon** raw game data (`raw.communitydragon.org`) | champion roles + playstyle ratings + damage type, Riot's own in-client rune/summoner-spell recommendations per position (`champion-rune-recommendations.json`), Arena / ARAM: Mayhem augment lists, names (EN/TR), rarities, tags and tooltips |
| `tools/curated/` (hand-maintained) | skill max order and archetype per champion, attribute overrides (engage/peel/waveclear…), item templates per archetype |
| Riot **Match-v5 + Timeline** (optional, needs a Riot API key) | anonymous counts per champion/position from Master+ and Diamond/Emerald ranked games (+ ARAM) on tr1, euw1, eun1, kr, na1: skill max order, opening skills, 3-item core, rune page, keystone + secondary tree, summoner spells, first boots, average CS/damage/vision/gold/deaths |

## Files

```
data/manifest.json                    {"schema": 1, "latest": "<patch>", "files": {"all": "<patch>/all.json"}}
data/<patch>/all.json                 everything below in one file — what the app downloads
data/<patch>/champions.json           index: roles, positions, damage type, attributes, archetype
data/<patch>/champions/<Id>.json      per champion: skill order + builds per position and "ARAM"
                                      (runes 2–3 pages, spells, starter/boots/core/situational items)
data/<patch>/items.json               items with stats and derived flags (antiheal, armorpen, anticrit, stasis…)
data/<patch>/runes.json               rune trees + stat shards (EN/TR)
data/<patch>/summoners.json           summoner spells (EN/TR)
data/<patch>/augments.json            {"ARENA": […], "MAYHEM": […]} with affinity keywords (no win rates)
data/<patch>/aggregate_counts.json    raw anonymous Match-v5 counts, accumulated across runs (input)
data/<patch>/aggregates.json          recommendations derived from the counts, with sample sizes (merged by build_data.py)
```

The app loads its on-disk cache (`~/Library/Application Support/Galio/data/`) or the bundled copy
(`Galio/Resources/BundledData/`), then checks `https://raw.githubusercontent.com/kpostaagasi/galio/main/data/manifest.json`
and downloads a newer patch when one is published.

## Commands

```bash
python3 tools/build_data.py --bundle      # rebuild data for the latest patch + refresh the bundled copy
python3 -m unittest tools/test_pipeline.py
tools/update_data.sh                      # rebuild, (optionally) aggregate, commit + push if changed
python3 tools/aggregate_matches.py --budget-minutes 45   # sample matches (key from env or ~/.hermes/secrets/riot_api_key)
python3 tools/aggregate_matches.py --derive-only         # re-derive aggregates.json from the committed counts
GALIO_AGG_MINUTES=10 tools/update_data.sh                # rebuild + bounded aggregation + publish
```

## Match-v5 aggregation

- **Accumulating, never double counting.** `aggregate_counts.json` holds per champion → position
  (`TOP`…`UTILITY`, or `ARAM`) `games`, `wins` and option tables (`skillMax`, `skillStart`, `core`,
  `runePages`, `runeTrees`, `spells`, `boots`; each option is `[games, wins]`) plus summed per-game
  `stats`. The IDs of counted (or rejected) matches live in `tools/.cache/processed_matches.json`
  (gitignored, per patch), so repeated runs add new matches only. A new patch starts from zero.
- **Anonymous.** PUUIDs are held in memory only to list match IDs; no PUUIDs, Riot IDs, names or
  match IDs are written to `data/`.
- **Sampling.** Regional clusters run in parallel (each routing value has its own rate limit):
  europe = tr1 + euw1 + eun1, asia = kr, americas = na1. Players come from Challenger, Grandmaster,
  Master (league-v4) and Diamond I/II, Emerald I (league-exp-v4); per player the last ranked solo
  (queue 420) and ARAM (450) games of the current patch are listed. Remakes and other queues are skipped.
- **Rate limits.** Per-host sliding windows configured from `X-App-Rate-Limit` (90 % of the limit),
  `Retry-After` honoured on 429, `--budget-minutes` bounds a run; progress is saved every 25 matches.
- **Thresholds** (constants at the top of `aggregate_matches.py`): a champion/position needs
  ≥ 20 games and ≥ 10 % of the champion's Rift games before it overrides rule data; options need
  ≥ 5 games; skill orders ≥ 20 games. When a champion has ≥ 40 sampled Rift games, only its observed
  positions are listed (otherwise Riot's position list is kept and observed ones are put first).
- **Ranking.** The most popular option wins; among options with at least half the top count, a
  smoothed win rate (internal only, Rift/ARAM builds) breaks near-ties. The raw counts keep `wins`
  for that purpose, but **no win rate is written to `aggregates.json` / `all.json` or shown in the
  app** — the UI says "most popular in N sampled games". Augment / Arena item win rates are never
  collected at all.
- **Benchmarks.** Per champion/position averages (CS/min, damage to champions/min, vision/min,
  gold/min, deaths) power the post-game comparison of the player's *own* numbers.

### Key handling

The scripts read `RIOT_API_KEY`, or — when it is unset — the file `~/.hermes/secrets/riot_api_key`.
The key is never printed; every log line passes through a redaction filter for `RGAPI-…`.

Automation: `.github/workflows/data.yml` rebuilds weekly (Wednesday 05:23 UTC) and on demand; on the
VPS the same can run from cron via `tools/update_data.sh`.

## Riot API key (optional)

1. Create a key on https://developer.riotgames.com (personal keys expire after 24 h; a registered
   product key is needed for regular use).
2. Put it in `~/.hermes/secrets/riot_api_key` (mode 600) or `export RIOT_API_KEY=…`. **Never commit it.**
3. Run `tools/update_data.sh`. Without a key the script re-derives from the committed counts.
