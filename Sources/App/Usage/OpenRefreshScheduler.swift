import CursorBarDomain
import Foundation

/// Debounces rapid menu/dashboard open events into one refresh pass.
@MainActor
final class OpenRefreshScheduler {
    private var pending: Set<OpenRefreshSurface> = []
    private var task: Task<Void, Never>?
    private let debounceNanoseconds: UInt64

    init(debounceNanoseconds: UInt64 = 350_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    func schedule(_ surface: OpenRefreshSurface, fire: @escaping (Set<OpenRefreshSurface>) -> Void) {
        pending.insert(surface)
        task?.cancel()
        task = Task { [weak self, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            let surfaces = self.pending
            self.pending.removeAll()
            fire(surfaces)
        }
    }

    func resetForTests() {
        task?.cancel()
        task = nil
        pending.removeAll()
    }
}
