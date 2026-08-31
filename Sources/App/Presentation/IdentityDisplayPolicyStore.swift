import CursorBarDomain
import Foundation

/// Tiny UserDefaults store for email reveal/mask. Defaults to mask.
struct IdentityDisplayPolicyStore {
    private let key = "identityDisplayPolicy"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> IdentityDisplayPolicy {
        guard let raw = defaults.string(forKey: key),
              let policy = IdentityDisplayPolicy(rawValue: raw)
        else {
            return .maskEmail
        }
        return policy
    }

    func save(_ policy: IdentityDisplayPolicy) {
        defaults.set(policy.rawValue, forKey: key)
    }
}
