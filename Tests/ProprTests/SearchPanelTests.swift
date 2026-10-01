import AppKit
import Foundation
import Testing
import WebKit

@testable import Propr

struct SearchPanelTests {
    @Test("Only Google, DuckDuckGo, and AI appear in lookup")
    func availableProviders() {
        #expect(SearchProvider.allCases == [.google, .duckDuckGo, .ai])
    }

    @Test(
        "Each web provider searches the complete edited phrase",
        arguments: SearchProvider.allCases.filter { $0 != .ai }
    )
    func providerSearchURL(provider: SearchProvider) {
        let query = "rejection & Swift/Unicode 👋"
        let url = provider.searchURL(for: query)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        #expect(url?.scheme == "https")
        #expect(components?.queryItems?.contains { $0.value == query } == true)

        switch provider {
        case .google:
            #expect(url?.host == "www.google.com")
        case .duckDuckGo:
            #expect(url?.host == "duckduckgo.com")
        case .ai:
            Issue.record("AI should not be treated as a web provider")
        }
    }

    @Test("Empty queries do not navigate", arguments: SearchProvider.allCases)
    func emptyQuery(provider: SearchProvider) {
        #expect(provider.searchURL(for: "  \n") == nil)
    }

    @MainActor
    @Test("Web results use Scry's desktop Safari presentation without blanket styling")
    func scryWebPresentation() {
        let google = SearchWebPresentation.makeConfiguration(for: .google)
        #expect(google.websiteDataStore === WKWebsiteDataStore.default())
        #expect(google.applicationNameForUserAgent == "Safari/605.1.15")
        #expect(google.defaultWebpagePreferences.preferredContentMode == .recommended)
        #expect(google.userContentController.userScripts.count == 1)
        #expect(google.userContentController.userScripts[0].injectionTime == .atDocumentEnd)
        #expect(google.userContentController.userScripts[0].source.contains("dismissConsent"))

        let duckDuckGo = SearchWebPresentation.makeConfiguration(for: .duckDuckGo)
        #expect(duckDuckGo.userContentController.userScripts.count == 1)
        #expect(duckDuckGo.userContentController.userScripts[0].injectionTime == .atDocumentStart)
        #expect(duckDuckGo.userContentController.userScripts[0].source.contains(".results--main"))
        #expect(SearchWebPresentation.makeConfiguration(for: .ai)
            .userContentController.userScripts.isEmpty)
    }

    @Test("AI lookup sends the latest query with Propr's endpoint and credentials")
    func aiLookupRequest() throws {
        let selection = ModelSelection(
            id: UUID(), displayName: "Test Model", endpointID: UUID(),
            modelName: "test-model", baseURL: "https://api.example.com/v1"
        )
        let request = try AILookupRequest(
            query: "the edited query", selection: selection,
            apiKey: "test-key", imageContext: nil
        ).makeURLRequest()
        let body = try #require(request.httpBody)
        let payload = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(payload["messages"] as? [[String: Any]])

        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(payload["model"] as? String == "test-model")
        #expect(payload["temperature"] as? Double == 0.4)
        #expect(messages[0]["content"] as? String == AILookupRequest.systemPrompt)
        #expect(messages[1]["content"] as? String == "What does the edited query mean?")
        #expect(payload["max_tokens"] as? Int == 160)
        #expect(AILookupRequest.systemPrompt.contains("slang meaning"))
    }

    @Test("Direct questions stay direct while words become meaning questions")
    func aiLookupPrompt() {
        #expect(AILookupRequest.userPrompt(for: "integration") == "What does integration mean?")
        #expect(AILookupRequest.userPrompt(for: "What is integration?") == "What is integration?")
        #expect(AILookupRequest.userPrompt(for: "Explain integration") == "Explain integration")
    }

    @MainActor
    @Test("AI answer renders Markdown and reflows tables for the narrow panel")
    func aiAnswerFormatting() {
        let answer = """
            **Integration** connects separate parts.

            | Term | Meaning |
            | --- | --- |
            | *Slang* | Social inclusion |

            See [more](https://example.com).
            """
        let rendered = SearchAnswerFormatter.render(answer)
        #expect(rendered.string.contains("Integration connects separate parts."))
        #expect(rendered.string.contains("Slang\nMeaning: Social inclusion"))
        #expect(rendered.string.contains("See more."))
        #expect(!rendered.string.contains("**"))
        #expect(!rendered.string.contains("| --- |"))
        let boldRange = (rendered.string as NSString).range(of: "Integration")
        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let linkRange = (rendered.string as NSString).range(of: "more")
        #expect(rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
            == URL(string: "https://example.com"))
    }

    @Test("Optional image context is included only when supplied")
    func aiLookupImageContext() throws {
        let selection = ModelSelection(
            id: UUID(), displayName: "Test Model", endpointID: UUID(),
            modelName: "test-model", baseURL: "https://api.example.com/v1"
        )
        let image = SearchImageContext(data: Data([1, 2, 3]), mimeType: "image/png")
        let payload = AILookupRequest(
            query: "What is this?", selection: selection,
            apiKey: "", imageContext: image
        ).payload
        let messages = try #require(payload["messages"] as? [[String: Any]])
        let segments = try #require(messages[1]["content"] as? [[String: Any]])

        #expect(segments[0]["text"] as? String == "What is this?")
        let imageURL = try #require(segments[1]["image_url"] as? [String: String])
        #expect(imageURL["url"] == "data:image/png;base64,AQID")
    }
}
