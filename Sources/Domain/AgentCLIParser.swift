import Foundation

public enum AgentUsageGroup: String, Sendable, Equatable, CaseIterable, Codable {
    case tokens
    case family
    case activity
    case time
    case models
}

public enum AgentCLIRequest: Sendable, Equatable {
    case list(json: Bool)
    case label(target: String, text: String?)
    case renewals(json: Bool)
    case usage(group: AgentUsageGroup?, seat: String?, json: Bool)
    case switchAccount(target: String, force: Bool)
    case help
}

public struct AgentCLIParseError: Error, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Argv parser for `cursor-accounts`. No package dependency.
public enum AgentCLIParser {
    public static func parse(_ args: [String]) -> Result<AgentCLIRequest, AgentCLIParseError> {
        var json = false
        var force = false
        var group: AgentUsageGroup?
        var seat: String?
        var positional: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--json":
                json = true
            case "--force":
                force = true
            case "--group":
                index += 1
                guard index < args.count else {
                    return .failure(AgentCLIParseError("missing value for --group"))
                }
                guard let parsed = AgentUsageGroup(rawValue: args[index]) else {
                    return .failure(AgentCLIParseError("unknown usage group \(args[index])"))
                }
                group = parsed
            case "--seat":
                index += 1
                guard index < args.count else {
                    return .failure(AgentCLIParseError("missing value for --seat"))
                }
                seat = args[index]
            case "-h", "--help":
                return .success(.help)
            default:
                if arg.hasPrefix("-") {
                    return .failure(AgentCLIParseError("unknown flag \(arg)"))
                }
                positional.append(arg)
            }
            index += 1
        }

        let command = positional.first?.lowercased() ?? "list"
        let rest = Array(positional.dropFirst())
        switch command {
        case "list", "accounts":
            guard rest.isEmpty else {
                return .failure(AgentCLIParseError("list does not take arguments"))
            }
            return .success(.list(json: json))
        case "label":
            return parseLabel(rest)
        case "renewals", "renewal":
            guard rest.isEmpty else {
                return .failure(AgentCLIParseError("renewals does not take arguments"))
            }
            return .success(.renewals(json: json))
        case "usage":
            guard rest.isEmpty else {
                return .failure(AgentCLIParseError("usage takes flags only"))
            }
            return .success(.usage(group: group, seat: seat, json: json))
        case "switch":
            guard rest.count == 1 else {
                return .failure(AgentCLIParseError("switch requires one account"))
            }
            return .success(.switchAccount(target: rest[0], force: force))
        case "help":
            return .success(.help)
        default:
            return .failure(AgentCLIParseError("unknown command \(command)"))
        }
    }

    public static let helpText = """
    cursor-accounts list [--json]
    cursor-accounts label <account|email> [<text>]
    cursor-accounts renewals [--json]
    cursor-accounts usage [--group tokens|family|activity|time|models] [--seat <account|email>] [--json]
    cursor-accounts switch <account|email> [--force]
    """

    private static func parseLabel(_ rest: [String]) -> Result<AgentCLIRequest, AgentCLIParseError> {
        guard let target = rest.first else {
            return .failure(AgentCLIParseError("label requires an account or email"))
        }
        if rest.count == 1 {
            return .success(.label(target: target, text: nil))
        }
        if rest.count == 2, rest[1].caseInsensitiveCompare("clear") == .orderedSame {
            return .success(.label(target: target, text: ""))
        }
        if rest[0].caseInsensitiveCompare("clear") == .orderedSame, rest.count == 2 {
            return .success(.label(target: rest[1], text: ""))
        }
        let text = rest.dropFirst().joined(separator: " ")
        return .success(.label(target: target, text: text))
    }
}
