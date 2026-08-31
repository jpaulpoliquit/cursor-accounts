import CursorBarDomain
import Foundation

/// Shared Connect POST boundary for DashboardService methods.
public struct DashboardConnectTransport: Sendable {
    public typealias Exchange = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum TransportError: Error, Sendable, Equatable {
        case rawAPIKeyCredential
        case transport
        case httpStatus(Int)
        case cancelled
    }

    public static let baseURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService")!

    private let exchange: Exchange
    private let baseURL: URL

    public init(
        exchange: Exchange? = nil,
        baseURL: URL = DashboardConnectTransport.baseURL
    ) {
        self.exchange = exchange ?? DashboardConnectTransport.urlSessionExchange
        self.baseURL = baseURL
    }

    public func post(method: String, access: ConnectReadyAccessToken, body: Data) async throws -> Data {
        let url = baseURL.appendingPathComponent(method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access.rawValue)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await exchange(request)
        } catch is CancellationError {
            throw TransportError.cancelled
        } catch {
            throw TransportError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw TransportError.transport
        }
        NSLog("CursorBar HTTP POST %@ %d", url.path, http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw TransportError.httpStatus(http.statusCode)
        }
        return data
    }

    /// Personal-account empty object. Never send teamId for individual seats.
    public static var personalEmptyBody: Data { Data("{}".utf8) }

    private static let urlSessionExchange: Exchange = { request in
        try await URLSession.shared.data(for: request)
    }
}

extension DashboardConnectTransport.TransportError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .rawAPIKeyCredential:
            "Dashboard requires a session JWT, not an API key"
        case .transport:
            "Dashboard request failed (network)"
        case .httpStatus(let code):
            "Dashboard request failed (HTTP \(code))"
        case .cancelled:
            "Dashboard request cancelled"
        }
    }

    public var debugDescription: String { description }
}
