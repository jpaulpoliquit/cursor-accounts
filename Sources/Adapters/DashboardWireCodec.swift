import CursorBarDomain
import Foundation

enum DashboardWireCodec {
    enum DecodeError: Error, Sendable, Equatable {
        case missingPlanUsage
        case missingRequiredPercent(String)
        case invalidPercent(String)
        case invalidBillingCycleEnd
        case invalidBillingCycleStart
        case missingPlanName
        case invalidIncludedAmountCents
        case invalidHardLimit
        case invalidCreditCents(String)
        case invalidPolicyCents(String)
        case invalidSpendUnits(String)
        case invalidTokenBuckets(String)
        case missingAccountIdentity
    }

    /// Wire int64 values may arrive as decimal strings or JSON numbers at the Connect edge.
    static func int64(fromDecimalString string: String) -> Int64? {
        Int64(string)
    }

    static func millisDate(fromDecimalString string: String) -> Date? {
        guard let millis = Double(string) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000.0)
    }

    static func amountCents(fromDecimalString string: String) throws -> AmountCents {
        guard let value = int64(fromDecimalString: string) else {
            throw DecodeError.invalidCreditCents(string)
        }
        return AmountCents(cents: value)
    }

    static func percent(_ value: Double, field: String) throws -> PercentUsed {
        guard let percent = PercentUsed(percent: value) else {
            throw DecodeError.invalidPercent(field)
        }
        return percent
    }
}

/// Decodes Connect int64 that may be a decimal string or a JSON number.
struct FlexibleInt64: Decodable, Sendable, Equatable {
    var value: Int64

    init(value: Int64) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            value = number
            return
        }
        if let number = try? container.decode(Int.self) {
            value = Int64(number)
            return
        }
        if let number = try? container.decode(Double.self), number.rounded() == number {
            value = Int64(number)
            return
        }
        if let string = try? container.decode(String.self), let parsed = Int64(string) {
            value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected int64 decimal string or number"
        )
    }
}

/// Decodes Connect int32 that may be a decimal string or a JSON number.
struct FlexibleInt32: Decodable, Sendable, Equatable {
    var value: Int32

    init(value: Int32) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int32.self) {
            value = number
            return
        }
        if let number = try? container.decode(Int.self),
           number >= Int(Int32.min), number <= Int(Int32.max)
        {
            value = Int32(number)
            return
        }
        if let number = try? container.decode(Double.self),
           number.rounded() == number,
           number >= Double(Int32.min),
           number <= Double(Int32.max)
        {
            value = Int32(number)
            return
        }
        if let string = try? container.decode(String.self), let parsed = Int32(string) {
            value = parsed
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected int32 decimal string or number"
        )
    }
}
