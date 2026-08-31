import CursorBarDomain
import Foundation

/// Bootstrap session check via GetCurrentPeriodUsage. Reuses DashboardClient decode/transport.
public struct DashboardSessionProbe: Sendable {
    public typealias Transport = DashboardConnectTransport.Exchange

    private let client: DashboardClient

    public init(client: DashboardClient = DashboardClient()) {
        self.client = client
    }

    public init(
        transport: Transport? = nil,
        endpoint: URL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    ) {
        if let transport {
            let base = endpoint.deletingLastPathComponent()
            let connect = DashboardConnectTransport(exchange: transport, baseURL: base)
            self.client = DashboardClient(transport: connect)
        } else {
            self.client = DashboardClient()
        }
    }

    public func probe(access: AccessToken) async -> Result<PeriodUsageProbeResult, SessionProbeFailure> {
        guard let ready = ConnectReadyAccessToken(access) else {
            return .failure(.transport)
        }
        return await probe(access: ready)
    }

    public func probe(access: ConnectReadyAccessToken) async -> Result<PeriodUsageProbeResult, SessionProbeFailure> {
        do {
            let detail = try await client.getCurrentPeriodUsage(access: access)
            return .success(
                PeriodUsageProbeResult(usage: detail.usage, displayMessage: detail.displayMessage)
            )
        } catch let error as DashboardClient.ClientError {
            return .failure(Self.map(error))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.transport)
        }
    }

    public static func parse(_ data: Data) throws -> PeriodUsageProbeResult {
        let detail = try DashboardClient.parsePeriodUsage(data)
        return PeriodUsageProbeResult(usage: detail.usage, displayMessage: detail.displayMessage)
    }

    private static func map(_ error: DashboardClient.ClientError) -> SessionProbeFailure {
        switch error {
        case .transport(.cancelled):
            return .cancelled
        case .transport(.httpStatus(let code)):
            return .httpStatus(code)
        case .transport(.rawAPIKeyCredential), .transport(.transport):
            return .transport
        case .decode, .invalidHardLimit:
            return .decode
        }
    }
}
