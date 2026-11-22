# Galio recommendation data

The app never scrapes third-party stat sites (op.gg, u.gg, mobalytics… forbid it). All data comes from:

| Source | Used for |
|---|---|
| Riot **Data Dragon** (`ddragon.leagueoflegends.com`) | patch list, champions (tags, stats, TR/EN names), items (stats, recipes, maps), runes, summoner spells, icons |
| **CommunityDragon** raw game data (`raw.communitydragon.org`) | champion roles + playstyle ratings + damage type, Riot's own in-client rune/summoner-spell recommendations per position (`champion-rune-recommendations.json`), Arena / ARAM: Mayhem augment lists, names (EN/TR), rarities, tags and tooltips |
| `tools/curated/` (hand-maintained) | skill max order and archetype per champion, attribute overrides (engage/peel/waveclear…), item templates per archetype |
| Riot **Match-v5 + Timeline** (optional, needs `RIOT_API_KEY`) | most common skill max order and first three completed items per champion/position in high-elo ranked games |

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
data/<patch>/aggregates.json          optional Match-v5 aggregates (anonymous counts only)
```

The app loads its on-disk cache (`~/Library/Application Support/Galio/data/`) or the bundled copy
(`Galio/Resources/BundledData/`), then checks `https://raw.githubusercontent.com/kpostaagasi/galio/main/data/manifest.json`
and downloads a newer patch when one is published.

## Commands

```bash
python3 tools/build_data.py --bundle      # rebuild data for the latest patch + refresh the bundled copy
python3 -m unittest tools/test_pipeline.py
tools/update_data.sh                      # rebuild, (optionally) aggregate, commit + push if changed
RIOT_API_KEY=... python3 tools/aggregate_matches.py --platform tr1 --region europe
```

Automation: `.github/workflows/data.yml` rebuilds weekly (Wednesday 05:23 UTC) and on demand; on the
VPS the same can run from cron via `tools/update_data.sh`.

## Riot API key (optional)

1. Create a key on https://developer.riotgames.com (personal keys expire after 24 h; a registered
   product key is needed for regular use).
2. `export RIOT_API_KEY=RGAPI-…` in the shell (or a local, untracked `.env`). **Never commit it.**
3. Run `tools/update_data.sh`. The aggregator stores only anonymous counts; PUUIDs are used in memory
   to list matches and are never written.
