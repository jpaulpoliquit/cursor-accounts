import CursorBarAdapters
import CursorBarDomain
import Foundation

extension AppModel {
    /// Single account-removal lifecycle at the App/usage boundary.
    /// Advances binding epoch synchronously, clears visible state, awaits actor purge before rebind refresh.
    func removeAccountCaches(seatID: SeatID) async {
        invalidateSignedInCredentials()
        let epoch = bindingEpochs.advance(for: seatID)
        usageBySeat[seatID] = nil
        persistUsageCards()
        usageRefresh.cancelForSeat(seatID)
        await usageSeries.purgeAccount(for: seatID, bindingEpoch: epoch)
        await refresher.invalidateBinding(seatID: seatID, epoch: epoch)
    }

    func applyUsageRefreshReport(_ report: UsageRefreshReport) {
        for (seatID, outcome) in report.outcomes {
            let captured = report.bindingEpochs[seatID] ?? bindingEpochs.current(for: seatID)
            guard bindingEpochs.isCurrent(seatID: seatID, epoch: captured) else { continue }
            switch outcome {
            case .refreshed(let snapshot):
                usageBySeat[seatID] = snapshot
                projectUsage(snapshot)
            case .failed(let message):
                annotateSeatDetail(seatID: seatID, detail: message)
            case .skippedSignedOut:
                break
            }
        }
        persistUsageCards()
    }

    private func annotateSeatDetail(seatID: SeatID, detail: String) {
        let seats = aggregate.seats.map { seat -> SeatSnapshot in
            guard seat.seatID == seatID else { return seat }
            return SeatSnapshot(
                seatID: seat.seatID,
                auth: seat.auth,
                email: seat.email,
                displayName: seat.displayName,
                pictureURL: seat.pictureURL,
                plan: seat.plan,
                usage: seat.usage,
                onDemand: seat.onDemand,
                authDetail: detail
            )
        }
        aggregate = AggregateSnapshot(seats: seats)
    }

    func startAfterRecovery() {
        if ideSwitch.phase.allowsDesktopImport {
            session.ensureStarted()
        } else {
            reloadShellFromKeychain()
            refreshCardsIfPolicyAllows(trigger: .bootstrap)
        }
        updates.quietRecheckIfDue()
    }

    func acknowledgeIDESwitch() {
        Task {
            await ideSwitch.acknowledge()
            bootstrapRecoveryTask = nil
            reproject()
            startAfterRecovery()
        }
    }

    func continuePendingAccountRestore() {
        Task {
            guard ConfirmationPrompts.confirmRestorePreviousAccount() else { return }
            await ideSwitch.continuePendingRestore()
            bootstrapRecoveryTask = nil
            reproject()
            startAfterRecovery()
        }
    }

    /// Joins one in-flight journal recovery. Later calls re-read live phase.
    func awaitStartupRecovery() async {
        if let task = bootstrapRecoveryTask {
            await task.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            _ = await self.ideSwitch.bootstrapPendingRecovery()
        }
        bootstrapRecoveryTask = task
        await task.value
        bootstrapRecoveryTask = nil
    }
}
