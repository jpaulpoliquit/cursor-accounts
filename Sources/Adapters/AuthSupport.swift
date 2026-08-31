import Foundation
import Security

public protocol AuthClock: Sendable {
    func now() -> Date
}

public struct SystemAuthClock: AuthClock {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol AuthSleeper: Sendable {
    func sleep(milliseconds: Int) async throws
}

public struct SystemAuthSleeper: AuthSleeper {
    public init() {}
    public func sleep(milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
}

public protocol AuthEntropy: Sendable {
    func randomBytes(_ count: Int) -> Data
    func randomUUID() -> UUID
}

public struct SystemAuthEntropy: AuthEntropy {
    public init() {}

    public func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    public func randomUUID() -> UUID { UUID() }
}

/// App-owned browser seam. Auth engine never imports SwiftUI/AppKit.
public protocol BrowserPresenting: Sendable {
    func present(loginURL: URL) async throws
}

/// No-op presenter for tests and Phase 3 (no real login browser).
public struct NullBrowserPresenter: BrowserPresenting {
    public init() {}
    public func present(loginURL: URL) async throws {}
}
