import CursorBarDomain
import Foundation

/// Single-owner bootstrap reconcile. Generation-scoped commits; prior aggregate stays visible while running.
@MainActor
public final class BootstrapSession {
    public private(set) var aggregate: AggregateSnapshot
    public private(set) var phase: BootstrapPhase = .pending

    public var onUpdate: (@MainActor (AggregateSnapshot, BootstrapPhase, [SeatID]) -> Void)?

    private let run: @Sendable () async throws -> BootstrapOrchestrator.Result
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastInvalidatedSeatIDs: [SeatID] = []

    public init(
        shell: AggregateSnapshot,
        run: @escaping @Sendable () async throws -> BootstrapOrchestrator.Result
    ) {
        self.aggregate = shell
        self.run = run
    }

    /// No-op while running or after settled. Use `refresh` for an explicit new generation.
    public func ensureStarted() {
        switch phase {
        case .running, .settled:
            return
        case .pending:
            begin(force: false)
        }
    }

    /// Starts a new generation even when already settled or running.
    public func refresh() {
        begin(force: true)
    }

    /// Invalidates the current generation. In-flight work cannot overwrite a newer aggregate or phase.
    public func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        if case .running = phase {
            phase = .pending
            publish()
        }
    }

    private func begin(force: Bool) {
        if !force {
            switch phase {
            case .running, .settled:
                return
            case .pending:
                break
            }
        }

        task?.cancel()
        generation &+= 1
        let token = generation
        phase = .running
        publish()
        task = Task { [run] in
            do {
                let result = try await run()
                await MainActor.run {
                    self.commit(token: token) {
                        self.aggregate = result.aggregate
                        self.phase = result.phase
                        self.lastInvalidatedSeatIDs = result.invalidatedSeatIDs
                        self.task = nil
                        self.publish()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.commit(token: token) {
                        self.phase = .pending
                        self.lastInvalidatedSeatIDs = []
                        self.task = nil
                        self.publish()
                    }
                }
            } catch {
                await MainActor.run {
                    self.commit(token: token) {
                        self.phase = .settled(.importFailed(message: "Bootstrap failed"))
                        self.lastInvalidatedSeatIDs = []
                        self.task = nil
                        self.publish()
                    }
                }
            }
        }
    }

    private func commit(token: UInt64, body: () -> Void) {
        guard token == generation else { return }
        body()
    }

    private func publish() {
        onUpdate?(aggregate, phase, lastInvalidatedSeatIDs)
        lastInvalidatedSeatIDs = []
    }
}
