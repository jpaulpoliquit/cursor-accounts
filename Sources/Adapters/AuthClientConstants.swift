import Foundation

/// Product/CLI auth endpoints and OAuth client id from installed Cursor build.
///
/// Evidence (2026.08.04 agent + Cursor.app workbench.desktop.main.js):
/// - websiteUrl `https://cursor.com`, apiUrl `https://api2.cursor.sh`
/// - prod `authClientId` / `zki` = `KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`
public enum AuthClientConstants {
    public static let websiteURL = URL(string: "https://cursor.com")!
    public static let apiBaseURL = URL(string: "https://api2.cursor.sh")!
    public static let oauthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    public static let redirectTarget = "cli"
    public static let loginMode = "login"

    public static let pollMaxAttempts = 150
    public static let pollBaseDelayMs = 1_000.0
    public static let pollMaxDelayMs = 10_000.0
    public static let pollBackoffFactor = 1.2
    public static let pollTransientFailureLimit = 3

    /// GetMe identity hydration after poll/exchange. Bounded; never unbounded All-Time style loops.
    public static let identityHydrationMaxAttempts = 4
    public static let identityHydrationBaseDelayMs = 400.0
    public static let identityHydrationMaxDelayMs = 2_000.0
    public static let identityHydrationBackoffFactor = 1.5

    /// Proactive refresh / API-key re-exchange window before JWT `exp`.
    public static let accessTokenRefreshSkew: TimeInterval = 60

    public static var pollURL: URL {
        apiBaseURL.appendingPathComponent("auth/poll")
    }

    public static var oauthTokenURL: URL {
        apiBaseURL.appendingPathComponent("oauth/token")
    }

    public static var exchangeAPIKeyURL: URL {
        apiBaseURL.appendingPathComponent("auth/exchange_user_api_key")
    }

    public static func pollDelayMs(attemptIndex: Int) -> Int {
        let raw = pollBaseDelayMs * pow(pollBackoffFactor, Double(attemptIndex))
        return Int(min(raw, pollMaxDelayMs))
    }

    public static func identityHydrationDelayMs(attemptIndex: Int) -> Int {
        let raw = identityHydrationBaseDelayMs * pow(identityHydrationBackoffFactor, Double(attemptIndex))
        return Int(min(raw, identityHydrationMaxDelayMs))
    }
}
