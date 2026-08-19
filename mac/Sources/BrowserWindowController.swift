import Cocoa
import WebKit

/// A window wrapping a single WKWebView. The main window and any OAuth popup
/// are both instances of this, so they share cookies, downloads and chrome.
final class BrowserWindowController: NSWindowController {
    let webView: WKWebView

    private var progressBar: NSProgressIndicator!
    private var errorView: ErrorView?
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var downloads: [WKDownload: URL] = [:]

    /// The default data store is shared by every window and persisted across
    /// launches, which is what makes "stay logged in" work.
    static let sharedConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = Config.userAgentSuffix
        return config
    }()

    // MARK: - Init

    /// - Parameter existingWebView: supplied by `window.open` handling, where WebKit
    ///   creates the view for us and we only provide the window around it.
    init(configuration: WKWebViewConfiguration? = nil, existingWebView: WKWebView? = nil, isPopup: Bool = false) {
        let config = configuration ?? BrowserWindowController.sharedConfiguration
        self.webView = existingWebView ?? WKWebView(frame: .zero, configuration: config)

        let size = isPopup ? NSSize(width: 620, height: 760) : NSSize(width: 1280, height: 860)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Config.appName
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 420, height: 480)
        window.backgroundColor = Palette.background
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        if !isPopup {
            window.setFrameAutosaveName("SentrelMainWindow")
        }
        setUpContentView()
        setUpWebView()
        if !isPopup {
            window.center()
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        progressObservation?.invalidate()
        titleObservation?.invalidate()
    }

    // MARK: - View setup

    private func setUpContentView() {
        guard let window = window else { return }

        let container = NSView()

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.underPageBackgroundColor = Palette.background // no flash on load or rubber-band scroll
        container.addSubview(webView)

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressBar)

        // Content starts below the title bar; the bar itself is transparent so the
        // page colour carries all the way up.
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            progressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: webView.topAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
        _ = topInset

        window.contentView = container
    }

    private func setUpWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.updateProgress(webView.estimatedProgress)
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            guard let title = webView.title, !title.isEmpty else { return }
            self?.window?.title = title
        }
    }

    private func updateProgress(_ value: Double) {
        if value >= 1.0 || value <= 0.0 {
            progressBar.isHidden = true
            progressBar.doubleValue = 0
        } else {
            progressBar.isHidden = false
            progressBar.doubleValue = value
        }
    }

    // MARK: - Navigation

    func loadHome() {
        load(Config.homeURL)
    }

    func load(_ url: URL) {
        dismissError()
        webView.load(URLRequest(url: url))
    }

    // MARK: - Error overlay

    private func showError(_ error: Error) {
        // Cancelled loads are normal (redirects, user-initiated stops) — not worth a screen.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        dismissError()
        guard let container = window?.contentView else { return }

        let view = ErrorView(message: nsError.localizedDescription) { [weak self] in
            self?.dismissError()
            if self?.webView.url == nil {
                self?.loadHome()
            } else {
                self?.webView.reload()
            }
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        errorView = view
    }

    private func dismissError() {
        errorView?.removeFromSuperview()
        errorView = nil
    }
}

// MARK: - NSWindowDelegate

extension BrowserWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared?.windowClosed(self)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Non-web schemes (mailto:, tel:, sentrel:) belong to the system.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // A plain link to somewhere else on the internet opens in the real browser;
        // subframes (embeds, iframes) are left alone.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, !Config.staysInApp(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Anything WebKit cannot render (CSV exports, PDFs marked as attachments)
        // becomes a download rather than a blank window.
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        dismissError()
        updateProgress(1.0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateProgress(1.0)
        showError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateProgress(1.0)
        showError(error)
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension BrowserWindowController: WKUIDelegate {
    /// `window.open` and `target="_blank"`. OAuth popups land here, and they only
    /// work if we hand back a web view that shares our configuration.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        if !Config.staysInApp(url) {
            NSWorkspace.shared.open(url)
            return nil
        }

        let popup = BrowserWindowController(configuration: configuration, isPopup: true)
        AppDelegate.shared?.register(popup)
        popup.showWindow(nil)
        popup.window?.makeKeyAndOrderFront(nil)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = Config.appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window!) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = Config.appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window!) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = Config.appName
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field

        alert.beginSheetModal(for: window!) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window!) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    /// Voice input needs the mic; granting it for our own origin avoids a second
    /// prompt on top of the system one.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let url = URL(string: "\(origin.protocol)://\(origin.host)")
        decisionHandler(url.map(Config.isAppHost) == true ? .grant : .prompt)
    }
}

// MARK: - WKDownloadDelegate

extension BrowserWindowController: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let destination = uniqueURL(in: downloads, named: suggestedFilename)
        self.downloads[download] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = downloads.removeValue(forKey: download) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: download)
        let alert = NSAlert(error: error)
        alert.messageText = "Download failed"
        if let window = window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func uniqueURL(in directory: URL, named filename: String) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 2
        repeat {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }
}
