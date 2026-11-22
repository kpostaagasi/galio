# Galio — agent rules

- Read `docs/SPEC.md` first; its compliance section (Riot policy) overrides any feature request: never automate game input (no auto skill-up, no auto-buy), never show augment/Arena win rates, only information visible to the player, client actions (rune import, item sets) only on explicit user click.
- Stack: Swift 6, SwiftUI, macOS 15+, Xcode project in `Galio/`. Tests: XCTest/Swift Testing; run `xcodebuild test` before every commit.
- Use recorded Live Client fixtures (`Fixtures/`) and the mock server for tests; never require a running game in CI/tests.
- No Riot artwork in the app icon; original art only.
- Commit messages and docs in English.
