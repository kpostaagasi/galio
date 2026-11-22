# Galio — League of Legends ARAM Mayhem companion for macOS

Owner: kpostaagasi. Platform: macOS 15+ on Apple Silicon (dev machine: MacBook Pro M4 Pro, Xcode installed).
Status: spec v0.1 (2026-11-22). Personal-use prototype first; public distribution only after Riot Developer Portal registration.

## 1. Job
Help the player make better ARAM Mayhem decisions with information that was available before the game:
1. **Augment helper** — when the 3 augment cards appear, show a tier badge (S/A/B/C/D) for each card *for the champion being played*, plus a one-line reason. Never auto-pick.
2. **Item helper** — show the next 2–3 item options, re-ordered against the visible enemy team composition (e.g. heavy AP → MR item first; healing → anti-heal), with the reason on each.
3. **Pre-game card** — in champion select / loading: core build, top augments, playstyle notes for the champion.

## 2. Hard compliance rules (Riot League Developer Policy — verify before each release)
Source: https://developer.riotgames.com/docs/lol (Game Integrity, Unapproved Use Cases).
- **Do NOT display augment win rates** ("Products cannot display win rates for Augments or Arena Mode items"). Use tiers derived from our own or curated data, never raw win-rate numbers.
- Do not dictate decisions: always show multiple ranked options with reasons; never "pick X now" and never auto-select or click in the game.
- Only information visible to the player in the client: own champion, own items, visible enemy champions/items from the Live Client Data API. No hidden info, no cooldown/timer tracking, no player de-anonymization, no opponent history/stats during the game.
- No game memory reading, no packet sniffing, no injection, no input automation into the game.
- Register the product on the Riot Developer Portal before sharing it with anyone else.

## 3. Data sources
- **Live Client Data API** (official, local): `https://127.0.0.1:2999/liveclientdata/allgamedata` (self-signed cert; pin Riot root cert or allow localhost only). Gives gameMode, active player, champion, items, all players' champions and items. Poll every 1–2 s only while a game is running.
- **League Client (LCU) API** (local, unsupported): optional for champion-select detection via lockfile. Treat as best-effort.
- **Static data**: Data Dragon / CommunityDragon for champion, item and augment names, icons, descriptions (respect their terms; cache per patch).
- **Augment tiers**: v1 = curated JSON per patch (`data/tiers/<patch>.json`) built by a script on the VPS from public tier lists *only where their terms allow*, otherwise from our own aggregation of Riot Match-v5 data with a personal API key. Store tiers, not win rates.
- **Augment offer detection**: the Live Client API does not expose offered augments. v1: on-device OCR of the 3 card titles with Apple Vision (`VNRecognizeTextRequest`) on a screen region (needs Screen Recording permission), fuzzy-matched against the augment list; fallback = quick search field where the user types 2–3 letters.

## 4. App shape
- SwiftUI app, menu-bar extra (status icon "Galio") + a floating, non-activating overlay panel (`NSPanel`, `.nonactivatingPanel`, `level = .floating`, click-through toggle). Works with LoL in borderless/windowed mode.
- Modules: `LiveClient` (polling + models), `Static` (DDragon cache), `Tiers` (patch JSON), `ItemAdvisor` (rule engine: enemy damage profile, healing, CC, tankiness → counter-item scores), `AugmentOCR` (Vision), `OverlayUI`.
- Settings: overlay position/opacity, hotkey to show/hide, OCR on/off, language TR/EN.
- Tests: unit tests for item rules and fuzzy matching with recorded `allgamedata` fixtures; a mock Live Client server for UI tests without a running game.

## 5. Milestones
- M0 Scaffold: Xcode project (SwiftUI, macOS 15, sandbox off for localhost TLS or with entitlement), menu-bar icon, mock Live Client server, CI-free local build + tests.
- M1 Live data: detect ARAM Mayhem game (gameMode/map), show own champion + enemy team in the overlay.
- M2 Item helper with rule engine + reasons.
- M3 Augment tiers (manual search first), then OCR detection.
- M4 Polish: Galio-themed icon/art (original art, no Riot assets in the app icon), TR/EN, settings, signing for personal use.

## 6. Non-goals (v1)
Windows support, auto item-set injection, account login, cloud backend, monetisation, any stats about other players.
