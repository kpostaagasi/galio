# Galio — agent rules

- Read `docs/SPEC.md` first; its compliance section (Riot policy) overrides any feature request: never automate game input (no auto skill-up, no auto-buy), never show augment/Arena win rates, only information visible to the player, client actions (rune import, item sets) only on explicit user click.
- Stack: Swift 5 language mode, SwiftUI, macOS 15+, XcodeGen `project.yml` (never commit the .xcodeproj), Apple frameworks only. Tests: XCTest. Swift cannot be compiled on the Linux VPS: GitHub Actions (`.github/workflows/build.yml`) is the compiler and test runner — keep pushes small and watch the run.
- UI strings: Turkish literals are String Catalog keys; add English to `tools/l10n/en.json` and run `python3 tools/l10n.py` (CI fails if the catalog is stale).
- Data: `tools/build_data.py --bundle` regenerates `data/<patch>/` and the bundled copy; `tools/make_fixtures.py` regenerates mock scenarios and test fixtures.
- Use recorded Live Client fixtures (`Fixtures/`) and the mock server for tests; never require a running game in CI/tests.
- No Riot artwork in the app icon; original art only.
- Commit messages and docs in English.
