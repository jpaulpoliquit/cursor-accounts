# CursorBar

Native macOS 14+ menu-bar app for managing Cursor accounts.

Bundle ID: `app.cursorbar`

## Build and run

Requires Xcode 15+ (Xcode 27 beta works) and macOS 14+.

```bash
# If you changed project.yml
brew install xcodegen   # once
xcodegen generate

open CursorBar.xcodeproj
```

Or from the CLI:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # if needed
xcodebuild -scheme CursorBar -destination 'platform=macOS' build
xcodebuild -scheme CursorBar -destination 'platform=macOS' test
```

Verification harness (prints exact commands; writes redacted logs under `.verify/`):

```bash
./Scripts/verify.sh unit        # xcodegen if needed + full tests
./Scripts/verify.sh adapters    # tests + static Keychain/secret checks
./Scripts/verify.sh smoke       # build, launch app, assert process, quit (no IDE restart)
CURSORBAR_LIVE=1 ./Scripts/verify.sh live-ro   # read-only Dashboard RPCs only
```

`live-write` is not implemented (needs dual env gates + exact revert). Smoke never relaunches Cursor IDE.

Run the app from Xcode (Product → Run) or launch the built binary under DerivedData. The process is a menu-bar agent (`LSUIElement`); look for `CB · N` in the menu bar.

**Switch account…** is an explicit menu action with confirmation. CursorBar uses one shared Cursor IDE profile (`~/Library/Application Support/Cursor`). Switching quits Cursor, replaces only scoped `cursorAuth/*` session rows in `state.vscdb`, relaunches the shared profile (no seat-specific `--user-data-dir`), and marks Active only after the DB JWT subject matches the target seat. Settings, extensions, history, and MCP config stay in the shared profile. Focus, sign-in, refresh, and on-demand never restart the IDE.

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

**Security.** App Sandbox is off for v1 so CursorBar can read and (only during account switch) narrowly update Cursor’s shared `state.vscdb`. Only Keychain service `app.cursorbar` is writable. Cursor-owned Keychain items are never written.

Account-switch DB writes are allowed only after Cursor has fully exited. The write set is scoped `cursorAuth/*` session rows from a Connect-ready plan (never `crsr_` API keys), applied in a `BEGIN IMMEDIATE` transaction with in-memory row backup, exact restore on failure, and identity verification before Ready/Active. Unrelated `ItemTable` rows and other tables are preserved. Fixture tests use `CursorAuthSessionStore.fixture` which refuses the live Application Support Cursor path.

## Phase 1 scope

- Import the logged-in Cursor desktop session without browser login
- Bind into the account roster (idempotent, no silent eviction)
- Show email, plan cache, and current-period usage on the seat card
- Menu bar label reflects signed-in count after bootstrap
