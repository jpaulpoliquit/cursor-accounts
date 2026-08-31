import Foundation

/// Marketing version `major.minor.patch`. Optional `v` prefix. No prerelease label.
public struct AppVersion: Sendable, Equatable, Comparable, Hashable, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func parse(_ raw: String) -> AppVersion? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        guard let major = parseComponent(parts[0]),
              let minor = parseComponent(parts[1])
        else {
            return nil
        }
        if parts.count == 2 {
            return AppVersion(major: major, minor: minor, patch: 0)
        }
        guard let patch = parseComponent(parts[2]) else { return nil }
        return AppVersion(major: major, minor: minor, patch: patch)
    }

    public var display: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    private static func parseComponent(_ raw: Substring) -> Int? {
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber), let value = Int(raw) else {
            return nil
        }
        return value
    }
}
