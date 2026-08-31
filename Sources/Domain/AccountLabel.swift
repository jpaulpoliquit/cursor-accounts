import Foundation

/// Resolved identity text for UI. Under `maskEmail` the Email case is unrepresentable.
public enum AccountLabel: Hashable, Sendable, Equatable {
    case email(Email)
    case displayName(DisplayName)
    /// Signed-in fallback with no display name. `disambiguator` is nil unless another unnamed account exists.
    case cursorAccount(disambiguator: Int?)

    public var text: String {
        switch self {
        case .email(let email):
            return email.value
        case .displayName(let name):
            return name.value
        case .cursorAccount(let disambiguator):
            if let disambiguator {
                return "Cursor account \(disambiguator)"
            }
            return "Cursor account"
        }
    }

    public var containsAtSign: Bool {
        text.contains("@")
    }
}

/// Sole identity formatting path. Views must not format email/local-part ad hoc.
public enum AccountLabelResolver {
    public struct Source: Sendable, Equatable {
        public let seatID: SeatID
        public let email: Email?
        public let displayName: DisplayName?

        public init(seatID: SeatID, email: Email?, displayName: DisplayName?) {
            self.seatID = seatID
            self.email = email
            self.displayName = displayName
        }
    }

    public static func resolve(
        policy: IdentityDisplayPolicy,
        source: Source
    ) -> AccountLabel {
        switch policy {
        case .revealEmail:
            if let displayName = source.displayName {
                return .displayName(displayName)
            }
            if let email = source.email {
                return .email(email)
            }
            return .cursorAccount(disambiguator: nil)
        case .maskEmail:
            if let displayName = source.displayName {
                return .displayName(displayName)
            }
            return .cursorAccount(disambiguator: nil)
        }
    }

    /// Assigns `Cursor account 2+` only when multiple signed-in unnamed labels collide.
    public static func disambiguate(_ labels: inout [SeatID: AccountLabel], connected: Set<SeatID>) {
        let unnamed = labels.keys.filter { seatID in
            connected.contains(seatID) && {
                if case .cursorAccount = labels[seatID] { return true }
                return false
            }()
        }.sorted()
        guard unnamed.count > 1 else { return }
        for (offset, seatID) in unnamed.enumerated() {
            labels[seatID] = .cursorAccount(disambiguator: offset + 1)
        }
    }

    /// Secondary email line for dashboard reveal mode only. Always nil under mask.
    public static func revealedEmail(
        policy: IdentityDisplayPolicy,
        source: Source
    ) -> Email? {
        switch policy {
        case .maskEmail:
            return nil
        case .revealEmail:
            return source.email
        }
    }

    /// Menu-root primary identity. Reveal prefers email so duplicate display names stay distinct.
    public static func menuPrimary(
        policy: IdentityDisplayPolicy,
        source: Source
    ) -> AccountLabel {
        switch policy {
        case .revealEmail:
            if let email = source.email {
                return .email(email)
            }
            if let displayName = source.displayName {
                return .displayName(displayName)
            }
            return .cursorAccount(disambiguator: nil)
        case .maskEmail:
            if let displayName = source.displayName {
                return .displayName(displayName)
            }
            return .cursorAccount(disambiguator: nil)
        }
    }

    /// Tooltip/help for menu rows. Never leaks email under mask.
    public static func menuHelpText(
        policy: IdentityDisplayPolicy,
        menuPrimary: AccountLabel,
        aliasLabel: AccountLabel
    ) -> String {
        switch policy {
        case .maskEmail:
            return menuPrimary.text
        case .revealEmail:
            if aliasLabel.text != menuPrimary.text, !aliasLabel.text.isEmpty {
                return "\(menuPrimary.text) · \(aliasLabel.text)"
            }
            return menuPrimary.text
        }
    }
}

/// Menu-root display-name fit. Dashboard and accessibility keep the full string.
public enum DisplayNameMenuFit {
    public static let maxRootCharacters = 28

    public static func rootTitle(_ full: String) -> String {
        guard full.count > maxRootCharacters else { return full }
        let end = full.index(full.startIndex, offsetBy: maxRootCharacters - 1)
        return String(full[..<end]) + "…"
    }
}
