import Foundation

/// Billing classification from `UsageEventDisplay.kind`. Not a product-surface / feature kind.
public enum BillingKind: Sendable, Equatable, Hashable {
    case unspecified
    case usageBased
    case userAPIKey
    case includedInPro
    case includedInBusiness
    case erroredNotCharged
    case abortedNotCharged
    case customSubscription
    case includedInProPlus
    case includedInUltra
    case freeCredit
    case unknown(String)

    public init(wireName: String?) {
        let raw = (wireName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw {
        case "", "USAGE_EVENT_KIND_UNSPECIFIED", "UNSPECIFIED":
            self = .unspecified
        case "USAGE_EVENT_KIND_USAGE_BASED", "USAGE_BASED":
            self = .usageBased
        case "USAGE_EVENT_KIND_USER_API_KEY", "USER_API_KEY":
            self = .userAPIKey
        case "USAGE_EVENT_KIND_INCLUDED_IN_PRO", "INCLUDED_IN_PRO":
            self = .includedInPro
        case "USAGE_EVENT_KIND_INCLUDED_IN_BUSINESS", "INCLUDED_IN_BUSINESS":
            self = .includedInBusiness
        case "USAGE_EVENT_KIND_ERRORED_NOT_CHARGED", "ERRORED_NOT_CHARGED":
            self = .erroredNotCharged
        case "USAGE_EVENT_KIND_ABORTED_NOT_CHARGED", "ABORTED_NOT_CHARGED":
            self = .abortedNotCharged
        case "USAGE_EVENT_KIND_CUSTOM_SUBSCRIPTION", "CUSTOM_SUBSCRIPTION":
            self = .customSubscription
        case "USAGE_EVENT_KIND_INCLUDED_IN_PRO_PLUS", "INCLUDED_IN_PRO_PLUS":
            self = .includedInProPlus
        case "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA", "INCLUDED_IN_ULTRA":
            self = .includedInUltra
        case "USAGE_EVENT_KIND_FREE_CREDIT", "FREE_CREDIT":
            self = .freeCredit
        default:
            self = .unknown(raw)
        }
    }

    public var accessibilityName: String {
        switch self {
        case .unspecified: "unspecified"
        case .usageBased: "usage based"
        case .userAPIKey: "user API key"
        case .includedInPro: "included in Pro"
        case .includedInBusiness: "included in Business"
        case .erroredNotCharged: "errored not charged"
        case .abortedNotCharged: "aborted not charged"
        case .customSubscription: "custom subscription"
        case .includedInProPlus: "included in Pro Plus"
        case .includedInUltra: "included in Ultra"
        case .freeCredit: "free credit"
        case .unknown(let raw): "unknown \(raw)"
        }
    }
}
