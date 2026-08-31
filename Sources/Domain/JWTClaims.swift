import Foundation

/// Locally decoded JWT payload fields. Signature is not verified; the server probe is authority.
public struct JWTClaims: Sendable, Equatable, Hashable {
    public let subject: String?
    public let expiresAt: Date?

    public init(subject: String?, expiresAt: Date?) {
        self.subject = subject
        self.expiresAt = expiresAt
    }

    public static func decode(jwt: String) -> JWTClaims? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let payloadData = base64URLDecode(String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        let subject = object["sub"] as? String
        let expiresAt: Date?
        if let exp = object["exp"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else if let expInt = object["exp"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(expInt))
        } else if let expNumber = object["exp"] as? NSNumber {
            expiresAt = Date(timeIntervalSince1970: expNumber.doubleValue)
        } else {
            expiresAt = nil
        }
        return JWTClaims(subject: subject, expiresAt: expiresAt)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
