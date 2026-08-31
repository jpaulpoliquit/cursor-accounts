import Foundation

/// Whether the user is looking at usage. Menu is ephemeral. Dashboard is the long-lived surface.
public enum UsageSurface: Sendable, Equatable, Hashable {
    case hidden
    case menuBar
    case dashboard
}

/// Kind of usage work a coordinator might start.
public enum UsageWorkKind: Sendable, Equatable, Hashable {
    case cardRefresh
    case seriesRefresh
    case historyWarm
}

/// What to do with one kind of work. Fetch never clears last-known.
public enum UsageWorkDecision: Sendable, Equatable, Hashable {
    case skip
    case showThenFetch
    case fetchNow
    case cancel
    case opportunistic
}

/// Single gate for background vs interactive usage work.
public enum UsageWorkPolicy {
    public static func surface(from openSurfaces: Set<OpenRefreshSurface>) -> UsageSurface {
        if openSurfaces.contains(.dashboard) {
            return .dashboard
        }
        if openSurfaces.contains(.menuBar) {
            return .menuBar
        }
        return .hidden
    }

    public static func retainsRawEventMonths(_ surface: UsageSurface) -> Bool {
        switch surface {
        case .dashboard:
            return true
        case .hidden, .menuBar:
            return false
        }
    }

    public static func decision(
        surface: UsageSurface,
        work: UsageWorkKind,
        trigger: UsageFetchTrigger,
        hasLastKnown: Bool,
        fetchedAt: Date?,
        now: Date = Date(),
        ttl: TimeInterval = UsageCachePolicy.ttl
    ) -> UsageWorkDecision {
        switch work {
        case .historyWarm:
            return historyWarmDecision(surface: surface)
        case .cardRefresh, .seriesRefresh:
            return refreshDecision(
                surface: surface,
                work: work,
                trigger: trigger,
                hasLastKnown: hasLastKnown,
                fetchedAt: fetchedAt,
                now: now,
                ttl: ttl
            )
        }
    }

    private static func historyWarmDecision(surface: UsageSurface) -> UsageWorkDecision {
        switch surface {
        case .dashboard:
            return .opportunistic
        case .menuBar:
            return .skip
        case .hidden:
            return .cancel
        }
    }

    private static func refreshDecision(
        surface: UsageSurface,
        work: UsageWorkKind,
        trigger: UsageFetchTrigger,
        hasLastKnown: Bool,
        fetchedAt: Date?,
        now: Date,
        ttl: TimeInterval
    ) -> UsageWorkDecision {
        switch (surface, work) {
        case (.hidden, .seriesRefresh), (.menuBar, .seriesRefresh):
            return .skip
        case (.hidden, .cardRefresh):
            switch trigger {
            case .signedIn:
                return networkDecision(
                    trigger: trigger,
                    hasLastKnown: hasLastKnown,
                    fetchedAt: fetchedAt,
                    now: now,
                    ttl: ttl
                )
            case .bootstrap:
                return hasLastKnown ? .skip : .fetchNow
            case .manual, .surfaceOpen:
                return .skip
            }
        case (.menuBar, .cardRefresh), (.dashboard, .cardRefresh), (.dashboard, .seriesRefresh):
            return networkDecision(
                trigger: trigger,
                hasLastKnown: hasLastKnown,
                fetchedAt: fetchedAt,
                now: now,
                ttl: ttl
            )
        case (.hidden, .historyWarm), (.menuBar, .historyWarm), (.dashboard, .historyWarm):
            return historyWarmDecision(surface: surface)
        }
    }

    private static func networkDecision(
        trigger: UsageFetchTrigger,
        hasLastKnown: Bool,
        fetchedAt: Date?,
        now: Date,
        ttl: TimeInterval
    ) -> UsageWorkDecision {
        switch trigger {
        case .signedIn, .manual:
            return hasLastKnown ? .showThenFetch : .fetchNow
        case .surfaceOpen, .bootstrap:
            if !hasLastKnown {
                return .fetchNow
            }
            if UsageCachePolicy.needsNetworkFetch(
                trigger: trigger,
                fetchedAt: fetchedAt,
                now: now,
                ttl: ttl
            ) {
                return .showThenFetch
            }
            return .skip
        }
    }
}
