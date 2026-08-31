import CursorBarDomain
import Foundation

/// Typed auth HTTP boundary. No `[String: Any]` in public API.
public struct AuthHTTPClient: Sendable {
    public typealias Exchange = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public struct SessionTokens: Sendable, Equatable {
        public let access: AccessToken
        public let refresh: RefreshToken

        public init(access: AccessToken, refresh: RefreshToken) {
            self.access = access
            self.refresh = refresh
        }
    }

    public enum PollResult: Sendable, Equatable {
        case pending
        case tokens(SessionTokens)
        case denied
        case malformed
        case httpStatus(Int)
        case transport
        case cancelled
    }

    private let exchange: Exchange

    public init(exchange: Exchange? = nil) {
        self.exchange = exchange ?? AuthHTTPClient.urlSessionExchange
    }

    public func poll(uuid: UUID, verifier: String) async -> PollResult {
        var components = URLComponents(url: AuthClientConstants.pollURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "uuid", value: uuid.uuidString.lowercased()),
            URLQueryItem(name: "verifier", value: verifier),
        ]
        guard let url = components.url else { return .transport }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await exchange(request)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .transport
        }

        guard let http = response as? HTTPURLResponse else { return .transport }
        switch http.statusCode {
        case 404:
            return .pending
        case 403:
            return .denied
        case 200:
            return Self.parsePollTokens(data)
        default:
            return .httpStatus(http.statusCode)
        }
    }

    public func refresh(refresh: RefreshToken) async throws -> SessionTokens {
        let body = RefreshTokenRequestBody(
            grant_type: "refresh_token",
            client_id: AuthClientConstants.oauthClientID,
            refresh_token: refresh.rawValue
        )
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw AuthError.malformed(stage: .refresh)
        }

        var request = URLRequest(url: AuthClientConstants.oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encoded

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await exchange(request)
        } catch is CancellationError {
            throw AuthError.cancelled(stage: .refresh)
        } catch {
            throw AuthError.transport(stage: .refresh)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.transport(stage: .refresh)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.http(stage: .refresh, status: http.statusCode)
        }
        return try Self.parseOAuthTokens(data)
    }

    public func exchangeAPIKey(_ key: APIKey) async throws -> SessionTokens {
        var request = URLRequest(url: AuthClientConstants.exchangeAPIKeyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key.rawValue)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await exchange(request)
        } catch is CancellationError {
            throw AuthError.cancelled(stage: .exchange)
        } catch {
            throw AuthError.transport(stage: .exchange)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.transport(stage: .exchange)
        }
        if http.statusCode == 403 {
            throw AuthError.denied(stage: .exchange)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.http(stage: .exchange, status: http.statusCode)
        }
        return try Self.parseExchangeTokens(data)
    }

    private static func parsePollTokens(_ data: Data) -> PollResult {
        struct Wire: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let access = AccessToken(wire.accessToken),
              let refresh = RefreshToken(wire.refreshToken)
        else {
            return .malformed
        }
        return .tokens(SessionTokens(access: access, refresh: refresh))
    }

    private static func parseOAuthTokens(_ data: Data) throws -> SessionTokens {
        struct Wire: Decodable {
            let access_token: String
            let refresh_token: String?
            let shouldLogout: Bool?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            throw AuthError.malformed(stage: .refresh)
        }
        if wire.shouldLogout == true {
            throw AuthError.denied(stage: .refresh)
        }
        guard let access = AccessToken(wire.access_token) else {
            throw AuthError.malformed(stage: .refresh)
        }
        // Prefer explicit refresh_token. When omitted, match installed desktop: store access as refresh.
        let refreshRaw = wire.refresh_token ?? wire.access_token
        guard let refresh = RefreshToken(refreshRaw) else {
            throw AuthError.malformed(stage: .refresh)
        }
        return SessionTokens(access: access, refresh: refresh)
    }

    private static func parseExchangeTokens(_ data: Data) throws -> SessionTokens {
        struct Wire: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let access = AccessToken(wire.accessToken),
              let refresh = RefreshToken(wire.refreshToken)
        else {
            throw AuthError.malformed(stage: .exchange)
        }
        return SessionTokens(access: access, refresh: refresh)
    }

    private static let urlSessionExchange: Exchange = { request in
        try await URLSession.shared.data(for: request)
    }
}

private struct RefreshTokenRequestBody: Encodable {
    let grant_type: String
    let client_id: String
    let refresh_token: String
}
