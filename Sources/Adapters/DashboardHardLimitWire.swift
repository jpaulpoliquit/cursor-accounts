import CursorBarDomain
import Foundation

struct GetHardLimitWireDTO: Decodable, Sendable {
    var hardLimit: Int32?
    var noUsageBasedAllowed: Bool?
    var hardLimitPerUser: Int32?
    var noUsageBasedAllowedPerUser: Bool?
    var isHardLimitPerUser: Bool?
}

struct SetHardLimitWireBody: Encodable, Sendable {
    var hardLimit: Int32
    var noUsageBasedAllowed: Bool
}

enum DashboardHardLimitWire {
    static func hardLimit(from dto: GetHardLimitWireDTO) throws -> HardLimit {
        do {
            return try HardLimit(
                noUsageBasedAllowed: dto.noUsageBasedAllowed,
                hardLimit: dto.hardLimit
            )
        } catch {
            throw DashboardWireCodec.DecodeError.invalidHardLimit
        }
    }

    static func encodeSetBody(mode: OnDemandMode) throws -> Data {
        let wire = HardLimit(mode: mode).setHardLimitWire
        let body = SetHardLimitWireBody(
            hardLimit: wire.hardLimit,
            noUsageBasedAllowed: wire.noUsageBasedAllowed
        )
        return try JSONEncoder().encode(body)
    }
}
