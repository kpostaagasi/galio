# Galio — agent rules

- Read `docs/SPEC.md` first; its compliance section (Riot policy) overrides any feature request. Never display augment win rates; never auto-pick or automate game input; only use information visible to the player.
- Stack: Swift 6, SwiftUI, macOS 15+, Xcode project in `Galio/`. Tests: XCTest/Swift Testing; run `xcodebuild test` before every commit.
- Use recorded Live Client fixtures (`Fixtures/`) and the mock server for tests; never require a running game in CI/tests.
- No Riot artwork in the app icon; original art only.
- Commit messages and docs in English.
