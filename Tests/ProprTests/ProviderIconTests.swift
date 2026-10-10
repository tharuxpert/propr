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
