import AppKit
import WebKit

/// Read-only lookup UI. Selection capture and gesture routing live outside this class.
@MainActor
final class SearchPanelController: NSObject {
    var onDismiss: (() -> Void)?
    var isVisible: Bool { panel?.isVisible ?? false }

    private var panel: SearchPanel?
    private let queryField = NSTextField()
    private let providerTabs = NSSegmentedControl()
    private let contentView = NSView()
    private let placeholder = NSTextField(labelWithString: "Select text or type a search")
    private let loadingIndicator = NSProgressIndicator()
    private var webView: WKWebView?
    private var aiResultView: NSView?
    private var pendingSearch: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var selectedProvider: SearchProvider = .google
    private var imageContext: SearchImageContext?
    private var searchGeneration = 0
    private var isDismissing = false

    func show(
        query: String,
        near screenPoint: CGPoint? = nil,
        imageContext: SearchImageContext? = nil
    ) {
        if panel == nil { createPanel() }
        guard let panel else { return }

        self.imageContext = imageContext
        queryField.stringValue = query
        // Every new lookup starts on the source chosen in Settings; switching tabs
        // inside the panel only lasts for that lookup.
        selectedProvider = SearchProvider.defaultForLookup
        providerTabs.selectedSegment = SearchProvider.allCases.firstIndex(of: selectedProvider) ?? 0
        place(panel, near: screenPoint)
        panel.orderFront(nil)
        panel.makeKey()
        panel.makeFirstResponder(queryField)
        queryField.selectText(nil)
        searchNow()
    }

    func hide() {
        guard let panel, panel.isVisible, !isDismissing else { return }
        isDismissing = true
        cancelActiveSearch()
        imageContext = nil
        panel.orderOut(nil)
        onDismiss?()
        isDismissing = false
    }

    private func createPanel() {
        let size = NSSize(width: 520, height: 580)
        let panel = SearchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.minSize = NSSize(width: 360, height: 300)
        panel.maxSize = NSSize(width: 900, height: 800)
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onResignKey = { [weak self] in self?.hide() }

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .windowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 15
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        panel.contentView = background

        let searchIcon = NSImageView(image: NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: "Search"
        ) ?? NSImage())
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(searchIcon)

        queryField.isBordered = false
        queryField.isBezeled = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 19)
        queryField.placeholderString = "Search selected text…"
        queryField.delegate = self
        queryField.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(queryField)

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close search") ?? NSImage(),
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close search"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(closeButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(separator)

        providerTabs.segmentCount = SearchProvider.allCases.count
        for (index, provider) in SearchProvider.allCases.enumerated() {
            providerTabs.setLabel(provider.title, forSegment: index)
        }
        providerTabs.trackingMode = .selectOne
        providerTabs.segmentStyle = .rounded
        providerTabs.selectedSegment = 0
        providerTabs.target = self
        providerTabs.action = #selector(providerChanged)
        providerTabs.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(providerTabs)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(loadingIndicator)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(contentView)

        placeholder.textColor = .secondaryLabelColor
        placeholder.font = .systemFont(ofSize: 14)
        placeholder.alignment = .center
        placeholder.lineBreakMode = .byWordWrapping
        placeholder.maximumNumberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            searchIcon.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),
            queryField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            queryField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            queryField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            closeButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -17),
            closeButton.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
            separator.topAnchor.constraint(equalTo: background.topAnchor, constant: 56),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            providerTabs.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 15),
            providerTabs.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 9),
            providerTabs.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: -9),
            loadingIndicator.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -19),
            loadingIndicator.centerYAnchor.constraint(equalTo: providerTabs.centerYAnchor),
            contentView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -16),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])

        self.panel = panel
    }

    private func place(_ panel: SearchPanel, near point: CGPoint?) {
        let screen = point.flatMap { target in
            NSScreen.screens.first(where: { $0.frame.contains(target) })
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let bounds = screen.visibleFrame
        let size = panel.frame.size
        let origin: CGPoint
        if let point {
            origin = CGPoint(
                x: min(max(point.x + 12, bounds.minX), bounds.maxX - size.width),
                y: min(max(point.y - size.height - 12, bounds.minY), bounds.maxY - size.height)
            )
        } else {
            origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func scheduleSearch() {
        cancelActiveSearch()
        let hasQuery = !queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSearch = hasQuery || (selectedProvider == .ai && imageContext?.isUsable == true)
        showPlaceholder(canSearch ? "Searching…" : "Select text or type a search")
        guard canSearch else { return }

        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.searchNow()
        }
    }

    private func searchNow() {
        cancelActiveSearch()

        guard isVisible else { return }
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty || (selectedProvider == .ai && imageContext?.isUsable == true) else {
            showPlaceholder("Select text or type a search")
            return
        }

        if selectedProvider == .ai {
            startAILookup(query: query)
            return
        }
        guard let url = selectedProvider.searchURL(for: query) else {
            showPlaceholder("Couldn’t form a search URL.")
            return
        }

        let webView = SearchWebPresentation.makeWebView(for: selectedProvider)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        self.webView = webView
        placeholder.isHidden = true
        loadingIndicator.startAnimation(nil)
        webView.load(URLRequest(url: url))
    }

    private func cancelActiveSearch() {
        searchGeneration &+= 1
        pendingSearch?.cancel()
        pendingSearch = nil
        aiTask?.cancel()
        aiTask = nil
        discardWebView()
        aiResultView?.removeFromSuperview()
        aiResultView = nil
        loadingIndicator.stopAnimation(nil)
    }

    private func startAILookup(query: String) {
        guard let selection = ModelStore.shared.selectedModel() else {
            showPlaceholder("No model selected. Choose one in Propr Settings.")
            return
        }
        let key = ModelStore.shared.apiKey(for: selection.endpointID) ?? ""
        guard !selection.requiresAPIKey || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showPlaceholder("No API key for the selected model. Add one in Propr Settings.")
            return
        }

        let request = AILookupRequest(
            query: query,
            selection: selection,
            apiKey: key,
            imageContext: imageContext
        )
        let generation = searchGeneration
        showPlaceholder("Looking up with AI…")
        loadingIndicator.startAnimation(nil)
        aiTask = Task { [weak self] in
            do {
                let answer = try await AILookupService.lookup(request)
                guard let self, !Task.isCancelled, self.searchGeneration == generation,
                      self.selectedProvider == .ai, self.isVisible else { return }
                self.loadingIndicator.stopAnimation(nil)
                self.showAIResult(answer, modelName: selection.displayName)
            } catch {
                guard let self, !Task.isCancelled, self.searchGeneration == generation,
                      self.selectedProvider == .ai, self.isVisible else { return }
                self.loadingIndicator.stopAnimation(nil)
                self.showPlaceholder(error.localizedDescription)
            }
        }
    }

    private func showAIResult(_ answer: String, modelName: String) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        let heading = NSTextField(labelWithString: "AI answer · \(modelName)")
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(heading)

        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(SearchAnswerFormatter.render(answer))
            textView.textContainer?.replaceLayoutManager(PillBackgroundLayoutManager())
            textView.drawsBackground = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 3, height: 8)
        }
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heading.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 19),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -19),
            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        aiResultView = container
        placeholder.isHidden = true
    }

    private func discardWebView() {
        guard let webView else { return }
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
    }

    private func showPlaceholder(_ message: String) {
        placeholder.stringValue = message
        placeholder.isHidden = false
    }

    @objc private func providerChanged() {
        guard SearchProvider.allCases.indices.contains(providerTabs.selectedSegment) else { return }
        selectedProvider = SearchProvider.allCases[providerTabs.selectedSegment]
        searchNow()
    }

    @objc private func closeTapped() { hide() }
}

extension SearchPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        scheduleSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            searchNow()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}

extension SearchPanelController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard self.webView === webView, isVisible else { return .cancel }
        if navigationAction.navigationType == .linkActivated,
            let url = navigationAction.request.url
        {
            if Self.canOpenExternally(url) {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
        return .allow
    }

    /// The results page is untrusted web content, so a clicked link is handed to the
    /// system only when it is an ordinary web link. Anything else (`file:`, `smb:`,
    /// or another app's URL scheme) could open local files, leak credentials to a
    /// remote share, or launch apps, so it is dropped.
    nonisolated static func canOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        return !(url.host() ?? "").isEmpty
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, isVisible else { return }
        loadingIndicator.stopAnimation(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error, from: webView)
    }

    private func handleNavigationError(_ error: Error, from webView: WKWebView) {
        guard self.webView === webView, isVisible else { return }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        discardWebView()
        loadingIndicator.stopAnimation(nil)
        showPlaceholder("Couldn’t load results. Press Return to try again.")
    }
}
