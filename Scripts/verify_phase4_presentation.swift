#!/usr/bin/env swift
import Foundation

#if canImport(CursorBarAdapters) && canImport(CursorBarDomain)
import CursorBarAdapters
import CursorBarDomain

@main
struct VerifyPhase4 {
    static func main() async {
        let keychain = SeatKeychainStore()
        let roster = (try? keychain.loadAll()) ?? []
        print("roster_count=\(roster.count)")
        for record in roster {
            print(
                "seat=\(record.seatID.rawValue) displayName=\(record.displayName?.value ?? "<nil>") email=\(record.email?.value ?? "<nil>")"
            )
        }

        let shell = AggregateSnapshot(seats: roster.map { $0.publicSnapshot() })
        let masked = SeatPresentationProjector.project(
            aggregate: shell,
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        print("MASK aggregate=\(masked.aggregateLine)")
        if let seat = masked.seats.first(where: { $0.auth == .signedIn || $0.auth == .needsReauth }) {
            print("MASK label=\(seat.label.text) revealedEmail=\(seat.revealedEmail?.value ?? "<nil>") ax=\(seat.accessibilityLabel)")
            assert(!seat.label.text.contains("@"), "masked label leaked @")
            assert(seat.revealedEmail == nil, "masked revealedEmail non-nil")
            assert(!seat.accessibilityLabel.contains("@"), "masked ax leaked @")
        }

        let revealed = SeatPresentationProjector.project(
            aggregate: shell,
            usageBySeat: [:],
            identityPolicy: .revealEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        if let seat = revealed.seats.first(where: { $0.auth == .signedIn || $0.auth == .needsReauth }) {
            print(
                "REVEAL label=\(seat.label.text) revealedEmail=\(seat.revealedEmail?.value ?? "<nil>")"
            )
        }

        let refresher = SeatUsageRefresher()
        let credentials = roster.compactMap {
            SeatUsageRefresher.SeatCredential(seatID: $0.seatID, access: $0.access)
        }
        if let first = credentials.first {
            let commit = await refresher.refresh(credential: first)
            switch commit {
            case .applied(let report):
                if case .refreshed(let snap) = report.outcomes[first.seatID] {
                    print(
                        "LIVE seat=\(snap.seatID.rawValue) auto=\(snap.period.usage.autoPercentUsed.percent) api=\(snap.period.usage.apiPercentUsed.percent) hardLimit=\(snap.hardLimit) credits=\(snap.credits)"
                    )
                    let live = SeatPresentationProjector.project(
                        aggregate: AggregateSnapshot(seats: [
                            roster.first(where: { $0.seatID == first.seatID })!.publicSnapshot(
                                usage: snap.period.usage
                            )
                        ]),
                        usageBySeat: [first.seatID: snap],
                        identityPolicy: .maskEmail,
                        focusedSeatID: first.seatID,
                        loginPhases: [:],
                        bootstrapPhase: .settled(.kept(first.seatID)),
                        usageRefreshPhase: .idle,
                        setHardLimitPhase: .idle
                    )
                    let presented = live.seats.first(where: { $0.seatID == first.seatID })!
                    print(
                        "LIVE_UI CursorModels=\(presented.autoPercent.map { Int($0.percent.rounded()) } ?? -1)% OtherModels=\(presented.apiPercent.map { Int($0.percent.rounded()) } ?? -1)% onDemand=\(presented.onDemand?.menuTitle ?? "<nil>") label=\(presented.label.text)"
                    )
                } else {
                    print("LIVE refresh outcome=\(String(describing: report.outcomes[first.seatID]))")
                }
            case .discarded:
                print("LIVE refresh discarded")
            }
        } else {
            print("LIVE skipped: no credentials")
        }
        print("VERIFY_OK")
    }
}
#else
print("Compile against CursorBar frameworks via xcodebuild test host instead.")
#endif
