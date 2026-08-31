import CursorBarAdapters
import CursorBarDomain
import Foundation

/// App-layer owner of account-switch phase + active-seat detection. Keeps AppModel thin.
@MainActor
final class IDESwitchCoordinator {
    private(set) var phase: IDESwitchPhase = .idle
    private(set) var desktopBoundSeatID: SeatID?
    private(set) var lastRejectMessage: String?

    private let engine: IDESwitchEngine
    private let detector: ActiveIDESeatDetector
    private var onPhaseChange: (() -> Void)?

    init(
        engine: IDESwitchEngine,
        detector: ActiveIDESeatDetector
    ) {
        self.engine = engine
        self.detector = detector
        desktopBoundSeatID = detector.detect()
    }

    func setPhaseObserver(_ observer: @escaping () -> Void) {
        onPhaseChange = observer
    }

    func refreshDesktopBound() {
        desktopBoundSeatID = detector.detect()
    }

    /// Resolve durable switch journal before any new switch. Never auto force-quits.
    func bootstrapPendingRecovery() async {
        let next = await engine.bootstrapPendingRecovery { [self] phase in
            await self.publishEnginePhase(phase)
        }
        phase = next
        desktopBoundSeatID = detector.detect()
    }

    func beginOpen(seatID: SeatID) async -> Bool {
        lastRejectMessage = nil
        let result = await engine.beginRequest(seatID: seatID)
        switch result {
        case .success(let next):
            phase = next
            onPhaseChange?()
            return true
        case .failure(let reason):
            phase = await engine.currentPhase()
            if phase.menuStatusText == nil {
                lastRejectMessage = reason.menuMessage
            }
            onPhaseChange?()
            return false
        }
    }

    func cancelOpen() async {
        await engine.cancelConfirmation()
        phase = await engine.currentPhase()
    }

    func confirmOpen(_ confirmed: ConfirmedIDEOpen) async {
        let next = await engine.runConfirmed(confirmed) { [self] phase in
            await self.publishEnginePhase(phase)
        }
        phase = next
        desktopBoundSeatID = detector.detect()
    }

    func forceQuitAfterTimeout() async {
        let next = await engine.forceQuitAfterTimeout { [self] phase in
            await self.publishEnginePhase(phase)
        }
        phase = next
        desktopBoundSeatID = detector.detect()
    }

    func acknowledge() async {
        lastRejectMessage = nil
        await engine.acknowledge()
        phase = await engine.currentPhase()
    }

    func continuePendingRestore() async {
        let next = await engine.continuePendingRestore { [self] phase in
            await self.publishEnginePhase(phase)
        }
        phase = next
        desktopBoundSeatID = detector.detect()
    }

    /// Engine callbacks hop here so phase and menu stay on MainActor for the awaited switch.
    private func publishEnginePhase(_ phase: IDESwitchPhase) {
        self.phase = phase
        onPhaseChange?()
    }
}
