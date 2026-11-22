# Galio — full League of Legends companion for macOS

Owner: kpostaagasi. Platform: macOS 15+ on Apple Silicon (user's machine: MacBook Pro M4 Pro).
Status: spec v0.2 (2026-11-22). Built by Hermes (Boss) on the VPS; compiled, tested and packaged on GitHub Actions macOS runners; delivered as `Galio.zip` via GitHub Releases. The user tests with real games.

## 1. Job
A complete LoL companion that follows the player through every phase of every game mode (Summoner's Rift normal/ranked, ARAM, ARAM Mayhem, Arena, URF/rotating modes, custom):

| Phase | Galio does |
|---|---|
| Lobby / queue | Detect queue and mode; patch highlights for the player's main champions. |
| Champion select | **Champion suggestions** for the player's role based on the team's composition (AP/AD mix, frontline, engage, peel, waveclear) and the enemy picks visible so far — always 3–5 options with reasons. Role tier info for picks/bans. |
| After lock-in | **Rune pages** (2–3 variants with reasons) with one-click import into the client; **summoner spells**; **skill order** (max order + first levels); **item build** (starter, core, situational), optionally exported as an in-client item set. |
| Loading / in game | Overlay: skill-order reminder, next item options re-ranked against the visible enemy team (with reasons), mode helpers (ARAM Mayhem / Arena augment tier badges). |
| Post game | Own performance vs. the plan (CS, damage, build followed), short learning notes. |

## 2. Hard compliance rules (Riot League Developer Policy — re-check before every release)
Sources: https://developer.riotgames.com/docs/lol (Game Integrity, Unapproved Use Cases), https://support.riotgames.com/en-us/riot/events/third-party-applications
- **Never automate gameplay input**: no auto skill level-up, no auto item purchase, no clicks/keys into the game. Skill order and items are *shown*; the player acts.
- Client conveniences offered by Riot-registered companions (rune page import, item-set export) only via the League Client API, only on an explicit user click, never during the live game.
- **No augment / Arena item win rates** anywhere — tiers (S–D) only.
- Never dictate: always several ranked options with reasons.
- Only information visible to the player: no hidden info, no cooldown/timer tracking, no enemy player history or stats during champ select or the game, no de-anonymisation (ranked champ-select names are hidden — never resolve them), no MMR/ELO estimates.
- No game memory reading, packet sniffing, injection or file modification.
- Register the product on the Riot Developer Portal before sharing it beyond the owner.

## 3. Data sources
- **League Client API (LCU)**, local, unsupported: lockfile at `/Applications/League of Legends.app/Contents/LoL/lockfile` (port + password, self-signed TLS). Gameflow phase, champ-select session (`/lol-champ-select/v1/session`), rune pages (`/lol-perks/v1/pages`), item sets, summoner spells; WebSocket subscription for live updates.
- **Live Client Data API** (official, local): `https://127.0.0.1:2999/liveclientdata/allgamedata` while in game — mode, champions, items, levels of all visible players.
- **Static data**: Data Dragon + CommunityDragon (champions, abilities, runes, items, augments, icons), cached per patch.
- **Recommendation data (the hard part)**:
  - v1: rule-based advisors + curated per-patch JSON (`data/<patch>/…`) for builds/runes/skill orders, generated on the VPS only from sources whose terms allow it.
  - v2: own aggregation pipeline on the VPS from Riot Match-v5/Timeline (needs a Riot production key after registration; the personal key is too rate-limited for broad stats). Publish aggregates per champion/role/patch as static JSON the app downloads.
- **Augment offer detection** (Mayhem/Arena): on-device Apple Vision OCR of the three card titles (Screen Recording permission), fuzzy-matched; manual search fallback.

## 4. App shape
- SwiftUI app: main window (champion pages, settings, history) + menu-bar extra + floating non-activating overlay panel (`NSPanel`, click-through toggle, hotkey). LoL in borderless/windowed mode for the overlay.
- Modules: `ClientBridge` (LCU lockfile, REST, WebSocket), `LiveGame` (Live Client polling), `StaticData`, `RecoData` (download + cache per patch), `Advisors` (`ChampionAdvisor`, `RuneAdvisor`, `SkillOrderAdvisor`, `ItemAdvisor`, `AugmentAdvisor`), `AugmentOCR`, `UI`.
- Testing without a game: recorded LCU / Live Client fixtures + a mock server; UI snapshot screenshots on the CI runner.
- Languages TR/EN. No Riot artwork in the app icon.

## 5. Milestones
- **M0 Scaffold**: XcodeGen project, menu-bar icon + main window, GitHub Actions macOS build/test, ad-hoc signed `Galio.zip` attached to a GitHub Release.
- **M1 Phase detection**: LCU lockfile + gameflow phase, Live Client game detection for all modes; overlay shows mode, own champion, enemy team.
- **M2 Champion select**: champ-select reader, champion suggestions by team composition, rune recommendation + one-click import, summoner spells, skill order display.
- **M3 In game**: item advisor vs. enemy team, skill-order reminder overlay, Mayhem/Arena augment tiers + OCR.
- **M4 Data pipeline**: VPS job producing per-patch recommendation JSON; in-app data auto-update.
- **M5 Post-game + polish**: summaries, settings, TR/EN, original icon/art; Developer ID signing + notarization once the Apple Developer account is approved; Riot Developer Portal registration.

## 6. Non-goals (v1)
Windows, cloud accounts, monetisation, stats about other identifiable players, gameplay automation.
