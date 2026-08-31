import CursorBarDomain
import Foundation

@MainActor
protocol ConfirmationGate: AnyObject {
    func confirmLocalSignOut(accountLabel: String) -> Bool
    func confirmOnDemandOff(accountLabel: String) -> Bool
    func confirmOnDemandUnlimited(accountLabel: String) -> Bool
    func promptFixedOnDemand(accountLabel: String, policy: UsagePolicy?) -> OnDemandMode?
}

/// Presents system confirmation, then invokes a private mutation continuation.
/// Views may only call intent entry points on this owner.
@MainActor
final class ConfirmationCommandCoordinator {
    private let gate: ConfirmationGate
    private var currentOnDemandMode: (SeatID) -> OnDemandMode? = { _ in nil }
    private var policyForSeat: (SeatID) -> UsagePolicy? = { _ in nil }
    private var accountLabel: (SeatID) -> String = { _ in "this account" }
    private var performSignOut: (SeatID) async -> Void = { _ in }
    private var performSetOnDemand: (SeatID, OnDemandMode) async -> Void = { _, _ in }

    private(set) var signOutInvocations = 0
    private(set) var setOnDemandInvocations = 0

    init(gate: ConfirmationGate) {
        self.gate = gate
    }

    func configure(
        currentOnDemandMode: @escaping (SeatID) -> OnDemandMode?,
        policyForSeat: @escaping (SeatID) -> UsagePolicy?,
        accountLabel: @escaping (SeatID) -> String,
        performSignOut: @escaping (SeatID) async -> Void,
        performSetOnDemand: @escaping (SeatID, OnDemandMode) async -> Void
    ) {
        self.currentOnDemandMode = currentOnDemandMode
        self.policyForSeat = policyForSeat
        self.accountLabel = accountLabel
        self.performSignOut = performSignOut
        self.performSetOnDemand = performSetOnDemand
    }

    func requestSignOutLocally(seatID: SeatID) {
        guard gate.confirmLocalSignOut(accountLabel: accountLabel(seatID)) else { return }
        signOutInvocations += 1
        Task { await performSignOut(seatID) }
    }

    func requestSetOnDemand(seatID: SeatID, mode: OnDemandMode) {
        if currentOnDemandMode(seatID) == mode { return }
        let label = accountLabel(seatID)
        let confirmed: Bool
        switch mode {
        case .off:
            confirmed = gate.confirmOnDemandOff(accountLabel: label)
        case .unlimited:
            confirmed = gate.confirmOnDemandUnlimited(accountLabel: label)
        case .fixed:
            return
        }
        guard confirmed else { return }
        setOnDemandInvocations += 1
        Task { await performSetOnDemand(seatID, mode) }
    }

    func requestSetOnDemandFixed(seatID: SeatID) {
        guard let mode = gate.promptFixedOnDemand(
            accountLabel: accountLabel(seatID),
            policy: policyForSeat(seatID)
        ) else { return }
        applyConfirmedOnDemand(seatID: seatID, mode: mode)
    }

    /// Dashboard editor already collected Off / Fixed / Unlimited. Do not stack another prompt.
    func applyConfirmedOnDemand(seatID: SeatID, mode: OnDemandMode) {
        if currentOnDemandMode(seatID) == mode { return }
        setOnDemandInvocations += 1
        Task { await performSetOnDemand(seatID, mode) }
    }
}
