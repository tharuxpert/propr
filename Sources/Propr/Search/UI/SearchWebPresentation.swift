import AppKit
import WebKit

/// The web presentation used by Scry's lookup panel, adapted to Propr's
/// provider enum. Search pages retain their own layout and colors.
@MainActor
enum SearchWebPresentation {
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"

    static func makeConfiguration(for provider: SearchProvider) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Safari/605.1.15"

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        if let script = provider.injectedJS {
            configuration.userContentController.addUserScript(WKUserScript(
                source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }
        return configuration
    }

    static func makeWebView(for provider: SearchProvider) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeConfiguration(for: provider))
        webView.customUserAgent = safariUserAgent
        return webView
    }
}
