import CursorBarDomain
import Foundation

/// GitHub Releases latest-feed boundary. Parses into `ReleaseFeedResult`.
public struct GitHubReleaseClient: Sendable {
    public typealias Exchange = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias TokenSource = @Sendable () async -> String?

    private let feedURL: URL
    private let exchange: Exchange
    private let tokenSource: TokenSource

    public init(
        feedURL: URL = AppUpdateFeed.githubLatestRelease,
        exchange: Exchange? = nil,
        tokenSource: TokenSource? = nil
    ) {
        self.feedURL = feedURL
        self.exchange = exchange ?? GitHubReleaseClient.urlSessionExchange
        self.tokenSource = tokenSource ?? GitHubReleaseClient.ghAuthToken
    }

    public func fetchLatest() async -> ReleaseFeedResult {
        var request = URLRequest(url: feedURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Cursor-Accounts", forHTTPHeaderField: "User-Agent")
        let token = await tokenSource()
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await exchange(request)
        } catch is CancellationError {
            return .unavailable
        } catch {
            return .unavailable
        }

        guard let http = response as? HTTPURLResponse else { return .unavailable }
        switch http.statusCode {
        case 200:
            return Self.parse(data)
        case 401, 403:
            return .unauthorized
        case 404:
            return token == nil ? .unauthorized : .empty
        default:
            return .unavailable
        }
    }

    static func parse(_ data: Data) -> ReleaseFeedResult {
        let wire: WireRelease
        do {
            wire = try JSONDecoder().decode(WireRelease.self, from: data)
        } catch {
            return .unavailable
        }
        if wire.draft == true {
            return .empty
        }
        guard let version = AppVersion.parse(wire.tag_name),
              let pageURL = URL(string: wire.html_url)
        else {
            return .unavailable
        }
        let assets = (wire.assets ?? []).compactMap { asset -> (String, URL)? in
            guard let url = URL(string: asset.browser_download_url) else { return nil }
            return (asset.name, url)
        }
        return .latest(
            PublishedRelease(
                version: version,
                title: (wire.name?.isEmpty == false ? wire.name : nil) ?? version.display,
                notes: wire.body ?? "",
                pageURL: pageURL,
                dmgURL: ReleaseDMGAsset.url(named: assets)
            )
        )
    }

    private static func urlSessionExchange(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    static func ghAuthToken() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: readGHAuthToken())
            }
        }
    }

    static func readGHAuthToken() -> String? {
        let process = Process()
        if let executable = ghExecutable() {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["auth", "token"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "auth", "token"]
        }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let raw = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, let raw, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    static func ghExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private struct WireRelease: Decodable, Sendable {
    var tag_name: String
    var name: String?
    var body: String?
    var html_url: String
    var draft: Bool?
    var assets: [WireAsset]?
}

private struct WireAsset: Decodable, Sendable {
    var name: String
    var browser_download_url: String
}
