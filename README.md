# Galio

<img src="assets/icon-1024.png" width="96" align="right" alt="Galio icon">

A League of Legends companion for macOS (Apple Silicon, macOS 15+): champion suggestions by team composition, rune pages with one-click import, summoner spells, skill order, item builds re-ranked against the visible enemy team, ARAM: Mayhem / Arena augment tiers (on-device OCR), post-game review and history. Turkish UI with English translation.

- Download: [Releases](https://github.com/kpostaagasi/galio/releases) → `Galio.zip` (first launch: right-click → Open).
- User guide (TR): [docs/USER_GUIDE.md](docs/USER_GUIDE.md) · Spec: [docs/SPEC.md](docs/SPEC.md) · Status: [docs/STATUS.md](docs/STATUS.md) · Data: [docs/DATA.md](docs/DATA.md)
- Try without a game: `open Galio.app --args --mock-game champselect` (also `champselect-locked`, `ingame`, `aram`, `mayhem`, `arena`, `postgame`).

Fair play: Galio never sends input to the game, never reads game memory, never shows other players' names or stats, and shows augment tiers only (no win rates). Client actions (rune page, summoner spells, item set) run only when you click, never during the live game.

Development: XcodeGen (`xcodegen generate`), Swift 5 mode, Apple frameworks only; CI on GitHub Actions builds, tests, launches every mock scenario and uploads screenshots.

Galio isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc.
