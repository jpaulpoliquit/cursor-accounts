# Agent notes

## Product

Cursor Accounts is a native macOS 14+ `LSUIElement` menu-bar app. The user-facing name is Cursor Accounts. Bundle ID and Keychain service stay `app.cursorbar`. Do not change those; it locks the author out of saved seats.

Internal Swift modules and types may stay `CursorBar*`. The Xcode scheme is `Cursor Accounts`. The built product is `Cursor Accounts.app`.

Unofficial and not affiliated with Cursor or Anysphere.

## Build

Prefer XcodeGen plus xcodebuild. If `project.yml` is newer than `CursorBar.xcodeproj/project.pbxproj`, run `xcodegen generate` first.

```bash
xcodegen generate
xcodebuild -scheme "Cursor Accounts" -destination 'platform=macOS' -configuration Release build
```

Xcode 15+ / Xcode 27 beta. When `/Applications/Xcode-beta.app` is present, scripts set `DEVELOPER_DIR` to that developer directory.

## Scripts

| Script | Role |
| --- | --- |
| `Scripts/install.sh` | xcodegen if needed, Release xcodebuild, `ditto` into `/Applications` (or `$INSTALL_DIR`), `xattr -cr`, PATH shortcut `cursor-accounts`. After a successful run, `/Applications/Cursor Accounts.app` exists and `cursor-accounts` runs from a new terminal. Does not leave the user in DerivedData. |
| `Scripts/package-dmg.sh` | Share path for strangers. Builds Release and writes `dist/Cursor-Accounts-0.2.0.dmg` with the app plus an `/Applications` symlink. |
| `Scripts/verify.sh` | Verify harness. Modes: `unit` (default), `adapters`, `smoke`, `live-ro`, `usage-restart`. `live-write` is not implemented. |

Do not run `verify.sh live-ro` or `live-write` unless the user explicitly asks. Smoke never relaunches Cursor IDE.

`dist/` is gitignored. Never git-add the DMG binary.

Keep the architecture invariant checks in `Scripts/verify.sh`.

## Share

Strangers get a disk image, not a tour of DerivedData.

```bash
./Scripts/install.sh          # /Applications/Cursor Accounts.app
./Scripts/package-dmg.sh      # dist/Cursor-Accounts-0.2.0.dmg
```

`APP_PATH="/Applications/Cursor Accounts.app" ./Scripts/package-dmg.sh` packages an already-built app and skips xcodebuild.

Check for Updates reads `https://api.github.com/repos/jpaulpoliquit/multi-cursor/releases/latest` using local `gh auth` when the repo is private. Do not embed a GitHub token. Do not add Sparkle until there is Developer ID signing and a public feed.

User-facing name is Cursor Accounts (Finder, menu, dashboard, alerts, DMG volume, Xcode scheme). Never ship “CursorBar”, “Cursor Bar”, “MultiCursor”, or “account slot” in UI. Internal Swift modules, `~/Library/Application Support/CursorBar`, and bundle ID `app.cursorbar` stay as they are.

Do not make the GitHub remote public. The MIT license is already in `LICENSE`; opening the remote is a separate human decision.

## Invariants

- Never write Cursor-owned Keychain names (`cursor-access-token`, `cursor-refresh-token`, `Cursor Safe Storage`).
- Only Keychain service `app.cursorbar` (and `app.cursorbar.test.*` in tests) is writable.
- Never commit `.verify/`, `.audit/`, tokens, `.env`, or Cursor session material.
- `.cursor/` stays gitignored.
- No user-facing "account slot" copy.
- App Sandbox off, Hardened Runtime on, Apple Development signing (`DEVELOPMENT_TEAM` `8DF2GCMHK5`).
- Do not add telemetry.
- Do not document session-injection steps beyond the high-level Switch account description in README.
- Do not make the GitHub remote public.
