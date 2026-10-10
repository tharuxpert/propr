import AppKit
import Foundation

/// Where to look for a provider's logo, and which of a page's icons to prefer.
///
/// Pure, so the choices can be tested without a network. Icons are only ever
/// fetched from the provider's own sites, never from a third-party favicon
/// service, which would learn every provider the user has configured.
enum ProviderIconSource {
    /// Sites to look on, most likely first: the preset's website when the endpoint
    /// came from one, then the API host and its parent domain (`api.groq.com` serves
    /// no icon, `groq.com` does). Empty for local and non-HTTPS endpoints.
    static func candidateSites(for baseURL: String) -> [URL] {
        guard let url = URL(string: baseURL),
            url.scheme?.lowercased() == "https",
            let host = url.host()?.lowercased(),
            !isLocal(host)
        else { return [] }

        var sites: [URL] = []
        if let website = BuiltInProvider.matching(baseURL: baseURL)?.website,
            let site = URL(string: website)
        {
            sites.append(site)
        }

        sites.append(URL(string: "https://\(host)")!)
        let labels = host.split(separator: ".")
        if labels.count >= 3 {
            sites.append(URL(string: "https://\(labels.dropFirst().joined(separator: "."))")!)
        }

        var seen = Set<String>()
        return sites.filter { seen.insert($0.host()?.lowercased() ?? "").inserted }
    }

    /// The icons a page declares in its `<link>` tags, best first: the
    /// apple-touch-icon (large and square), then by declared size. Monochrome
    /// Safari `mask-icon`s are skipped, and only HTTPS URLs are returned.
    static func iconURLs(inHTML html: String, page: URL) -> [URL] {
        var scored: [(url: URL, score: Int)] = []

        for tag in matches(of: #"<link\b[^>]*>"#, in: html) {
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                rel.contains("icon"), !rel.contains("mask-icon"),
                let href = attribute("href", in: tag),
                let url = URL(string: href, relativeTo: page)?.absoluteURL,
                url.scheme?.lowercased() == "https"
            else { continue }

            let score = rel.contains("apple-touch-icon") ? 1_000 : declaredSize(in: tag)
            scored.append((url, score))
        }

        // Stable sort keeps the page's order among equal scores.
        return scored.enumerated()
            .sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }
            .map(\.element.url)
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("127.")
            || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host == "::1"
            || host.hasPrefix("[")
    }

    /// The largest side named in `sizes`, 512 for a scalable `any`, and 16 when the
    /// page does not say, which is what an undeclared favicon usually is.
    private static func declaredSize(in tag: String) -> Int {
        guard let sizes = attribute("sizes", in: tag)?.lowercased() else { return 16 }
        if sizes.contains("any") { return 512 }
        return sizes.split(separator: " ")
            .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
            .max() ?? 16
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}

/// Fetches provider logos and keeps them, in memory and on disk, so Settings does
/// not hit the network every time it opens.
@MainActor
final class ProviderIconStore {
    static let shared = ProviderIconStore()

    private static let maxPageBytes = 512 * 1_024
    private static let maxIconBytes = 1_024 * 1_024

    private var memory: [String: NSImage] = [:]
    /// Hosts that had no usable icon this launch, so they are not retried on every
    /// redraw. Not persisted, so a site that adds an icon is picked up next launch.
    private var misses: Set<String> = []
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private let directory: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Propr/ProviderIcons", isDirectory: true)

    /// The logo if it is already known, without touching the network.
    func cachedIcon(for baseURL: String) -> NSImage? {
        guard let key = Self.key(for: baseURL) else { return nil }
        if let image = memory[key] { return image }
        guard let file = file(for: key), let image = NSImage(contentsOf: file) else { return nil }
        memory[key] = image
        return image
    }

    /// The logo, fetching it from the provider's site when it is not cached yet.
    func icon(for baseURL: String) async -> NSImage? {
        if let cached = cachedIcon(for: baseURL) { return cached }
        guard let key = Self.key(for: baseURL), !misses.contains(key) else { return nil }

        let sites = ProviderIconSource.candidateSites(for: baseURL)
        let task = inFlight[key] ?? Task.detached { await Self.fetchIconData(sites: sites) }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil

        guard let data, let image = NSImage(data: data) else {
            misses.insert(key)
            return nil
        }
        memory[key] = image
        save(data, for: key)
        return image
    }

    // MARK: - Network

    nonisolated private static func fetchIconData(sites: [URL]) async -> Data? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        for site in sites {
            var candidates: [URL] = []
            if let (page, finalURL) = await download(site, from: session, limit: maxPageBytes),
                let html = String(data: page, encoding: .utf8) ?? String(data: page, encoding: .isoLatin1)
            {
                candidates += ProviderIconSource.iconURLs(inHTML: html, page: finalURL)
            }
            // Many sites serve /favicon.ico without declaring it, and some block
            // the page itself but not the icon.
            candidates.append(site.appending(path: "favicon.ico"))

            for candidate in candidates {
                if let (data, _) = await download(candidate, from: session, limit: maxIconBytes),
                    let image = NSImage(data: data), image.isValid, image.size.width > 0
                {
                    return data
                }
            }
        }
        return nil
    }

    /// Downloads at most `limit` bytes over HTTPS, returning nil on any failure.
    nonisolated private static func download(
        _ url: URL, from session: URLSession, limit: Int
    ) async -> (Data, URL)? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("image/*,text/html;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        guard let (bytes, response) = try? await session.bytes(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let finalURL = http.url, finalURL.scheme?.lowercased() == "https",
            http.expectedContentLength <= Int64(limit)
        else { return nil }

        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return nil }
            }
        } catch {
            return nil
        }
        return data.isEmpty ? nil : (data, finalURL)
    }

    // MARK: - Disk

    private static func key(for baseURL: String) -> String? {
        URL(string: baseURL)?.host()?.lowercased()
    }

    private func file(for key: String) -> URL? {
        directory?.appendingPathComponent(key).appendingPathExtension("icon")
    }

    private func save(_ data: Data, for key: String) {
        guard let directory, let file = file(for: key) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
