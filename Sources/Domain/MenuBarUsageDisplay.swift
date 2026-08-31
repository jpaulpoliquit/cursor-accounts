import Foundation

/// What the status extra shows next to the Cursor Accounts mark.
public enum MenuBarUsageDisplay: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Yellow mark only.
    case icon
    /// `97 · 100 · $304.73 / $320`
    case usage

    public var showsNumbers: Bool { self == .usage }
}
