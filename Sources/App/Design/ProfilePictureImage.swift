import AppKit
import ImageIO
import Observation
import SwiftUI

/// Loads HTTPS profile photos independently of view lifetime.
/// WorkOS/Imgix will serve AVIF when asked; AppKit often cannot decode it.
struct ProfilePictureImage: View {
    let url: URL

    var body: some View {
        let _ = ProfilePictureLoader.shared.revision
        Group {
            if let image = ProfilePictureLoader.shared.cached(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: url) {
            await ProfilePictureLoader.shared.load(url)
        }
    }
}

@MainActor
@Observable
final class ProfilePictureLoader {
    static let shared = ProfilePictureLoader()

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private(set) var revision: UInt64 = 0
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: Set<URL> = []

    static func prefetch(_ urls: [URL]) {
        shared.prefetch(urls)
    }

    static func cached(for url: URL) -> NSImage? {
        shared.cached(for: url)
    }

    static func image(for url: URL) async -> NSImage? {
        await shared.load(url)
    }

    /// Unsigned Imgix/WorkOS: force a JPEG AppKit can paint.
    /// Signed URLs stay untouched — extra query items invalidate `s` / `sig`.
    nonisolated static func requestURL(for url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host.contains("workoscdn") || host.contains("imgix.net")
        else { return url }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = parts?.queryItems ?? []
        let signed = items.contains { item in
            ["s", "sig", "signature", "token"].contains(item.name.lowercased())
        }
        if signed { return url }
        if !items.contains(where: { $0.name == "fm" }) {
            items.append(URLQueryItem(name: "fm", value: "jpg"))
        }
        if !items.contains(where: { $0.name == "w" }) {
            items.append(URLQueryItem(name: "w", value: "96"))
        }
        parts?.queryItems = items
        return parts?.url ?? url
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            Task { await load(url) }
        }
    }

    func cached(for url: URL) -> NSImage? {
        cache.object(forKey: Self.requestURL(for: url) as NSURL)
    }

    @discardableResult
    func load(_ url: URL) async -> NSImage? {
        let fetchURL = Self.requestURL(for: url)
        if let cached = cache.object(forKey: fetchURL as NSURL) {
            return cached
        }
        guard inflight.insert(fetchURL).inserted else {
            return cache.object(forKey: fetchURL as NSURL)
        }
        defer { inflight.remove(fetchURL) }
        var request = URLRequest(url: fetchURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png,image/webp,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                  let image = Self.decode(data)
            else { return nil }
            cache.setObject(image, forKey: fetchURL as NSURL)
            revision += 1
            return image
        } catch {
            return nil
        }
    }

    nonisolated private static func decode(_ data: Data) -> NSImage? {
        if let image = NSImage(data: data), image.isValid, !image.representations.isEmpty {
            return image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}
