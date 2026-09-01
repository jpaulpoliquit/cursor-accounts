# Cursor Accounts

Native macOS 14+ menu-bar app for managing Cursor accounts.

Unofficial and not affiliated with Cursor or Anysphere. MIT licensed.

The Finder name is **Cursor Accounts**. Bundle ID stays `app.cursorbar` so saved Keychain seats keep working.

## Get Cursor Accounts

Requires macOS 14 or later.

### Disk image (for other people)

1. Open `Cursor-Accounts-0.2.1.dmg`.
2. Drag **Cursor Accounts** onto **Applications**.
3. Open Cursor Accounts from Applications. It is a menu-bar agent (`LSUIElement`); look for the yellow mark with the active account and usage.

```bash
./Scripts/package-dmg.sh
# writes dist/Cursor-Accounts-0.2.1.dmg  (gitignored — do not commit the binary)
```

The image contains Cursor Accounts, an Applications shortcut, and a short Read Me.

Check for Updates reads the latest GitHub Release of this repo. The remote is private, so the app uses your local `gh auth` login and never embeds a token. Publish a release whose asset is `Cursor-Accounts-*.dmg`. The menu rechecks quietly once a day and turns into Update Available when a newer tag exists. It does not replace the app. View Release and Download DMG open the published GitHub files.

This build is signed with Apple Development, not Developer ID. On another Mac, Gatekeeper blocks the first launch until you right-click Cursor Accounts.app, choose Open, and confirm. Sparkle-style auto-replace needs Developer ID plus a public feed. That is not this build.

### This Mac, from source

```bash
brew install xcodegen                # once
./Scripts/install.sh                 # Release build → /Applications/Cursor Accounts.app
INSTALL_DIR="$HOME/Applications" ./Scripts/install.sh
```

After a successful run, `/Applications/Cursor Accounts.app` exists and `cursor-accounts` is on your `PATH` (`/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`). The script does not leave you in DerivedData.

```bash
cursor-accounts list
cursor-accounts usage
cursor-accounts --help
```

## Build from source

Requires Xcode 15+ (Xcode 27 beta works), macOS 14+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate       # if you changed project.yml
open CursorBar.xcodeproj
```

Verification harness (prints exact commands; writes redacted logs under `.verify/`):

```bash
./Scripts/verify.sh unit        # xcodegen if needed + full tests
./Scripts/verify.sh adapters    # tests + static Keychain/secret checks
./Scripts/verify.sh smoke       # build, launch app, assert process, quit (no IDE restart)
```

`live-write` is not implemented (needs dual env gates + exact revert). Smoke never relaunches Cursor IDE.

The Xcode scheme is **Cursor Accounts**. The built product is `Cursor Accounts.app`. Swift modules stay `CursorBar*`.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # if needed
xcodebuild -scheme "Cursor Accounts" -destination 'platform=macOS' build
xcodebuild -scheme "Cursor Accounts" -destination 'platform=macOS' test
```

**Switch account…** is an explicit menu action with confirmation. Cursor Accounts uses one shared Cursor IDE profile (`~/Library/Application Support/Cursor`). Switching quits Cursor, replaces only scoped `cursorAuth/*` session rows in `state.vscdb`, relaunches the shared profile (no seat-specific `--user-data-dir`), and marks Active only after the DB JWT subject matches the target seat. Settings, extensions, history, and MCP config stay in the shared profile. Focus, sign-in, refresh, and on-demand never restart the IDE.

Legacy per-seat directories under `~/Library/Application Support/CursorBar/IDEProfiles/` are left on disk and are no longer launched. Migration is silent by default.

## Architecture

| Layer | Path | Rules |
| --- | --- | --- |
| Domain | `Sources/Domain` | Foundation only. Typed contracts, pure derives. No SwiftUI, AppKit, SQLite, Security, or networking. |
| Adapters | `Sources/Adapters` | Cursor desktop session SQLite, `app.cursorbar` Keychain, Dashboard probe, bootstrap bind, account-switch inject/restore. |
| App shell | `Sources/App` | Composition root, MenuBarExtra, Dashboard UI. Features must not touch token raw values. |
| Design | `Sources/App/Design` | Motion tokens (Reduce Motion aware). |
| Tests | `Tests/DomainTests`, `Tests/AdaptersTests` | Domain invariants plus adapter fixtures (never live tokens). |

**Composition.** `AppModel` paints a credential-free shell from Keychain, then `BootstrapOrchestrator` imports the active Cursor desktop session into Seat 1 (or the matching existing seat) and probes current-period usage.

**Security.** App Sandbox is off for v1 so Cursor Accounts can read and (only during account switch) narrowly update Cursor's shared `state.vscdb`. Only Keychain service `app.cursorbar` is writable. Cursor-owned Keychain items are never written.

Account-switch DB writes are allowed only after Cursor has fully exited. The write set is scoped `cursorAuth/*` session rows from a Connect-ready plan (never `crsr_` API keys), applied in a `BEGIN IMMEDIATE` transaction with in-memory row backup, exact restore on failure, and identity verification before Ready/Active. Unrelated `ItemTable` rows and other tables are preserved. Fixture tests use `CursorAuthSessionStore.fixture` which refuses the live Application Support Cursor path.

## Phase 1 scope

- Import the logged-in Cursor desktop session without browser login
- Bind into the account roster (idempotent, no silent eviction)
- Show email, plan cache, and current-period usage on the seat card
- Menu bar label reflects signed-in count after bootstrap
