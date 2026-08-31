import CursorBarAdapters
import CursorBarDomain
import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateController {
    var lastCheck: AppUpdateCheck?
    var isChecking = false

    private let client: GitHubReleaseClient
    private let installed: AppVersion
    private let defaults: UserDefaults
    private let lastCheckKey = "appUpdateLastCheckAt"
    private let snapshotKey = "appUpdateLastCheck"
    private let present: (AppUpdateCheck) -> Void

    init(
        client: GitHubReleaseClient = GitHubReleaseClient(),
        installed: AppVersion? = nil,
        defaults: UserDefaults = .standard,
        present: @escaping (AppUpdateCheck) -> Void = UpdateCheckAlert.present
    ) {
        self.client = client
        self.installed = installed
            ?? AppVersion.parse(
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            )
            ?? AppVersion(major: 0, minor: 1, patch: 0)
        self.defaults = defaults
        self.present = present
        if let data = defaults.data(forKey: snapshotKey),
           let stored = try? JSONDecoder().decode(AppUpdateCheck.self, from: data)
        {
            lastCheck = AppUpdateCheck.restore(stored, installed: self.installed)
        }
    }

    var menuTitle: String {
        if case .available = lastCheck {
            return "Update Available…"
        }
        return "Check for Updates…"
    }

    func checkAndPresent() async {
        present(await refresh())
    }

    func quietRecheckIfDue(now: Date = Date()) {
        let last = defaults.object(forKey: lastCheckKey) as? Date
        guard AppUpdateQuietPolicy.shouldRecheck(lastCheck: last, now: now) else { return }
        Task { _ = await refresh() }
    }

    private func refresh() async -> AppUpdateCheck {
        if isChecking {
            return lastCheck ?? .unavailable
        }
        isChecking = true
        defer { isChecking = false }
        let incoming = AppUpdateCheck.decide(installed: installed, feed: await client.fetchLatest())
        let check = AppUpdateCheck.merging(previous: lastCheck, incoming: incoming)
        lastCheck = check
        defaults.set(Date(), forKey: lastCheckKey)
        if let data = try? JSONEncoder().encode(check) {
            defaults.set(data, forKey: snapshotKey)
        }
        return check
    }
}
