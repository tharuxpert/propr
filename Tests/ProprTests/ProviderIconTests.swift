import Foundation
import Testing

@testable import Propr

/// Provider logos come from the provider's own sites. These pin down which sites
/// are tried and which of a page's icons wins, without touching the network.
struct ProviderIconTests {
    private func hosts(_ baseURL: String) -> [String] {
        ProviderIconSource.candidateSites(for: baseURL).compactMap { $0.host() }
    }

    @Test("A preset's website is tried before its API host")
    func presetWebsiteFirst() {
        #expect(hosts("https://api.groq.com/openai/v1") == ["groq.com", "api.groq.com"])
        #expect(hosts("https://openrouter.ai/api/v1") == ["openrouter.ai"])
    }

    @Test("A custom endpoint tries its host, then the parent domain")
    func customEndpointFallsBackToParent() {
        #expect(hosts("https://api.example.com/v1") == ["api.example.com", "example.com"])
    }

    @Test("Local and plain HTTP endpoints never fetch a logo", arguments: [
        "http://127.0.0.1:11434/v1",
        "https://localhost:1234/v1",
        "https://box.local/v1",
        "http://api.example.com/v1",
    ])
    func localEndpointsSkipped(_ baseURL: String) {
        #expect(ProviderIconSource.candidateSites(for: baseURL).isEmpty)
    }

    @Test("Only HTTPS public domains may be fetched", arguments: [
        ("https://groq.com/favicon.ico", true),
        ("https://cdn.prod.website-files.com/a/touch.png", true),
        ("https://xn--bcher-kva.example/icon.png", true),
        ("http://groq.com/favicon.ico", false),
        ("https://192.168.1.1/logo.png", false),
        ("https://10.0.0.1/", false),
        ("https://127.0.0.1/", false),
        ("https://2130706433/", false),
        ("https://0x7f000001/", false),
        ("https://[::1]/", false),
        ("https://[fe80::1]/", false),
        ("https://169.254.169.254/latest", false),
        ("https://router/", false),
        ("https://localhost/", false),
        ("https://nas.local/", false),
        ("https://wiki.corp/", false),
        ("https://metadata.google.internal/", false),
    ])
    func fetchAllowList(_ link: String, allowed: Bool) {
        #expect(ProviderIconSource.isAllowed(URL(string: link)!) == allowed)
    }

    @Test("Icon links on a page cannot point at the local network")
    func iconLinksStayPublic() {
        let html = """
            <link rel="apple-touch-icon" href="https://192.168.1.1/admin/reboot">
            <link rel="icon" href="https://router.local/logo.png" sizes="512x512">
            <link rel="icon" href="/favicon.png">
            """
        let urls = ProviderIconSource.iconURLs(inHTML: html, page: URL(string: "https://evil.example.com")!)

        #expect(urls.map(\.absoluteString) == ["https://evil.example.com/favicon.png"])
    }

    @Test("The apple-touch-icon wins, then the largest declared size")
    func iconRanking() {
        let html = """
            <link rel="icon" href="/favicon.ico">
            <link rel='icon' href='/icon-96.png' sizes='96x96'>
            <link rel="mask-icon" href="/mask.svg">
            <link href="https://cdn.example.com/touch.png" rel="apple-touch-icon">
            <link rel="stylesheet" href="/site.css">
            <link rel="icon" href="http://insecure.example.com/icon.png" sizes="512x512">
            """
        let urls = ProviderIconSource.iconURLs(inHTML: html, page: URL(string: "https://example.com/home")!)

        #expect(urls.map(\.absoluteString) == [
            "https://cdn.example.com/touch.png",
            "https://example.com/icon-96.png",
            "https://example.com/favicon.ico",
        ])
    }
}
