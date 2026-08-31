import CryptoKit
import Foundation

/// CLI-parity PKCE for deep-control login.
/// Verifier is base64url(random 32 bytes). Challenge hashes the verifier *string* UTF-8 bytes.
public enum PKCE {
    public struct Pair: Sendable, Equatable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String, challenge: String) {
            self.verifier = verifier
            self.challenge = challenge
        }
    }

    public static func makePair(entropy: any AuthEntropy) -> Pair {
        let raw = entropy.randomBytes(32)
        let verifier = base64URLEncode(raw)
        return Pair(verifier: verifier, challenge: challenge(forVerifier: verifier))
    }

    public static func challenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func deepControlLoginURL(
        challenge: String,
        uuid: UUID,
        websiteURL: URL = AuthClientConstants.websiteURL,
        redirectTarget: String = AuthClientConstants.redirectTarget
    ) -> URL {
        var components = URLComponents(url: websiteURL.appendingPathComponent("loginDeepControl"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid.uuidString.lowercased()),
            URLQueryItem(name: "mode", value: AuthClientConstants.loginMode),
            URLQueryItem(name: "redirectTarget", value: redirectTarget),
        ]
        return components.url!
    }
}
