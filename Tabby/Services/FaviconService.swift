import Foundation
import AppKit

final class FaviconService {
    static let shared = FaviconService()
    private var cache: [String: Data] = [:]

    private init() {}

    // Fetches the page title and favicon for a URL.
    // Returns (title, faviconData) — either can be nil on failure.
    func fetchMetadata(for urlString: String) async -> (title: String?, faviconData: Data?) {
        guard let url = URL(string: urlString) else { return (nil, nil) }

        async let title = fetchTitle(url: url)
        async let favicon = fetchFavicon(for: urlString)

        return await (title, favicon)
    }

    /// Favicon only — tries site `/favicon.ico`, then DuckDuckGo, then Google s2.
    func fetchFavicon(for urlString: String) async -> Data? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }

        let cacheKey = host
        if let cached = cache[cacheKey] { return cached }

        if let data = await fetchDirectFaviconICO(url: url) {
            cache[cacheKey] = data
            return data
        }

        if let data = await fetchImageData(from: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")) {
            cache[cacheKey] = data
            return data
        }

        var google = URLComponents(string: "https://www.google.com/s2/favicons")
        google?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "32")
        ]
        if let googleURL = google?.url, let data = await fetchImageData(from: googleURL) {
            cache[cacheKey] = data
            return data
        }

        return nil
    }

    // MARK: - Title

    private func fetchTitle(url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: Constants.faviconFetchTimeout)
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        // Simple regex-free title extraction
        if let range = html.range(of: "<title", options: .caseInsensitive),
           let end = html.range(of: "</title>", options: .caseInsensitive, range: range.upperBound..<html.endIndex) {
            let inner = String(html[range.upperBound..<end.lowerBound])
            // Strip the > that closes the opening tag
            if let gtRange = inner.range(of: ">") {
                let raw = String(inner[gtRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : htmlDecoded(raw)
            }
        }
        return nil
    }

    // MARK: - Favicon

    private func fetchDirectFaviconICO(url: URL) async -> Data? {
        guard var baseComps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        baseComps.path = "/favicon.ico"
        baseComps.query = nil
        baseComps.fragment = nil
        guard let faviconURL = baseComps.url else { return nil }
        return await fetchImageData(from: faviconURL)
    }

    private func fetchImageData(from url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Constants.faviconFetchTimeout)
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count >= 32,
              NSImage(data: data) != nil else {
            return nil
        }
        return data
    }

    // MARK: - HTML entity decoding (minimal)

    private func htmlDecoded(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#039;", "'"), ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}
