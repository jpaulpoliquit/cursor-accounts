import XCTest

/// Documented manual checklist for a future live A→B→A switch.
/// This suite never mutates Cursor. It only skips unless explicitly armed, and even then
/// refuses to run automated live switching from CI/agent contexts.
final class ManualAccountSwitchChecklistTests: XCTestCase {
    func testManualSharedProfileSwitchChecklistIsDocumentedAndNotAutoExecuted() throws {
        let armed =
            ProcessInfo.processInfo.environment["CURSORBAR_MANUAL_ACCOUNT_SWITCH"] == "1"
        guard armed else {
            throw XCTSkip(
                """
                Manual checklist (do not automate against a live Cursor session):
                1. Confirm two hydrated seats in CursorBar Keychain.
                2. Note current Cursor settings/extensions/MCP.
                3. Switch account A → B from the menu; confirm restart copy.
                4. After Ready/Active on B, confirm email/plan and unchanged settings.
                5. Switch B → A; confirm Active returns to A and settings still unchanged.
                6. On inject/verify failure, confirm rollback restores the prior account.
                Arm with CURSORBAR_MANUAL_ACCOUNT_SWITCH=1 only for human operators.
                """
            )
        }
        throw XCTSkip(
            "Live A→B→A switching is intentionally not automated; follow the checklist manually."
        )
    }
}
