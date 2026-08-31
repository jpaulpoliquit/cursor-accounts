import Foundation

public struct PublishedRelease: Sendable, Equatable, Codable {
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let dmgURL: URL?

    public init(version: AppVersion, title: String, notes: String, pageURL: URL, dmgURL: URL?) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.dmgURL = dmgURL
    }
}

/// Outcome of one feed fetch after parse. Wire status codes stay in Adapters.
public enum ReleaseFeedResult: Sendable, Equatable {
    case latest(PublishedRelease)
    case empty
    case unauthorized
    case unavailable
}

/// What Check for Updates (and the quiet recheck) can show.
public enum AppUpdateCheck: Sendable, Equatable, Codable {
    case upToDate(installed: AppVersion)
    case available(PublishedRelease)
    case noPublishedRelease
    case unauthorized
    case unavailable

    public static func decide(installed: AppVersion, feed: ReleaseFeedResult) -> AppUpdateCheck {
        switch feed {
        case .latest(let release):
            if release.version > installed {
                return .available(release)
            }
            return .upToDate(installed: installed)
        case .empty:
            return .noPublishedRelease
        case .unauthorized:
            return .unauthorized
        case .unavailable:
            return .unavailable
        }
    }

    /// A later transport or auth miss keeps a known newer release.
    public static func merging(previous: AppUpdateCheck?, incoming: AppUpdateCheck) -> AppUpdateCheck {
        guard case .available(let known) = previous else {
            return incoming
        }
        switch incoming {
        case .unauthorized, .unavailable:
            return .available(known)
        case .available, .upToDate, .noPublishedRelease:
            return incoming
        }
    }

    public static func restore(_ stored: AppUpdateCheck, installed: AppVersion) -> AppUpdateCheck {
        if case .available(let release) = stored, release.version <= installed {
            return .upToDate(installed: installed)
        }
        return stored
    }
}

public enum ReleaseDMGAsset {
    public static func url(named assets: [(name: String, url: URL)]) -> URL? {
        assets.first { name, _ in
            name.hasPrefix("Cursor-Accounts-") && name.lowercased().hasSuffix(".dmg")
        }?.url
    }
}

public enum AppUpdateQuietPolicy {
    public static let defaultInterval: TimeInterval = 60 * 60 * 24

    public static func shouldRecheck(
        lastCheck: Date?,
        now: Date,
        interval: TimeInterval = defaultInterval
    ) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}

public enum AppUpdateFeed {
    public static let githubLatestRelease = URL(
        string: "https://api.github.com/repos/jpaulpoliquit/multi-cursor/releases/latest"
    )!
}

public enum AppUpdateCopy {
    public static func title(_ check: AppUpdateCheck) -> String {
        switch check {
        case .upToDate(let installed):
            return "\(ProductName.display) \(installed.display)"
        case .available(let release):
            return "\(ProductName.display) \(release.version.display) is available"
        case .noPublishedRelease:
            return "No published release"
        case .unauthorized:
            return "Release feed is private"
        case .unavailable:
            return "Could not check for updates"
        }
    }

    public static func message(_ check: AppUpdateCheck) -> String {
        switch check {
        case .upToDate:
            return "This is the latest published release."
        case .available(let release):
            let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if notes.isEmpty {
                return "A newer GitHub Release is published."
            }
            if notes.count <= 800 {
                return notes
            }
            return String(notes.prefix(800)) + "…"
        case .noPublishedRelease:
            return "Publish a GitHub Release with a Cursor-Accounts-*.dmg asset."
        case .unauthorized:
            return "Check for Updates uses your local GitHub login (gh auth). Sign in with GitHub CLI, then try again."
        case .unavailable:
            return "The release feed did not respond."
        }
    }
}
