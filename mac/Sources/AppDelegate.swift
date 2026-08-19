import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var mainWindow: BrowserWindowController?
    private var popups: [BrowserWindowController] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Clicking the Dock icon with no window open reopens the app rather than doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: - Windows

    private func showMainWindow() {
        if let existing = mainWindow {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = BrowserWindowController()
        mainWindow = controller
        controller.loadHome()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func register(_ popup: BrowserWindowController) {
        popups.append(popup)
    }

    func windowClosed(_ controller: BrowserWindowController) {
        if controller === mainWindow {
            mainWindow = nil
        }
        popups.removeAll { $0 === controller }
    }

    private var activeWebView: WKWebView? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)?.webView
            ?? mainWindow?.webView
    }

    // MARK: - Actions

    @objc private func reload(_ sender: Any?) {
        guard let webView = activeWebView else { return }
        // A page that failed to load has no URL to reload — send it home instead.
        if webView.url == nil {
            (NSApp.keyWindow?.windowController as? BrowserWindowController)?.loadHome()
        } else {
            webView.reload()
        }
    }

    @objc private func forceReload(_ sender: Any?) {
        activeWebView?.reloadFromOrigin()
    }

    @objc private func goBack(_ sender: Any?) {
        activeWebView?.goBack()
    }

    @objc private func goForward(_ sender: Any?) {
        activeWebView?.goForward()
    }

    @objc private func goHome(_ sender: Any?) {
        (NSApp.keyWindow?.windowController as? BrowserWindowController ?? mainWindow)?.loadHome()
    }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let url = activeWebView?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyCurrentURL(_ sender: Any?) {
        guard let url = activeWebView?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func zoomIn(_ sender: Any?) {
        guard let webView = activeWebView else { return }
        webView.pageZoom = min(webView.pageZoom + 0.1, 3.0)
    }

    @objc private func zoomOut(_ sender: Any?) {
        guard let webView = activeWebView else { return }
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }

    @objc private func zoomReset(_ sender: Any?) {
        activeWebView?.pageZoom = 1.0
    }

    @objc private func signOutAndClearData(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear all local data?"
        alert.informativeText = "This signs you out and removes cookies and cached files for \(Config.appName)."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.goHome(nil)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(Config.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Clear Local Data…", action: #selector(signOutAndClearData(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(Config.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(Config.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — without this, Cmd+C/V/A do not work in the web view's text fields.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = NSMenuItem(title: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatch)
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload(_:)), keyEquivalent: "r")
        let hardReload = NSMenuItem(title: "Reload Ignoring Cache", action: #selector(forceReload(_:)), keyEquivalent: "r")
        hardReload.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(hardReload)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreen)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Navigate menu
        let navMenuItem = NSMenuItem()
        let navMenu = NSMenu(title: "Navigate")
        navMenu.addItem(withTitle: "Back", action: #selector(goBack(_:)), keyEquivalent: "[")
        navMenu.addItem(withTitle: "Forward", action: #selector(goForward(_:)), keyEquivalent: "]")
        navMenu.addItem(.separator())
        let home = NSMenuItem(title: "Home", action: #selector(goHome(_:)), keyEquivalent: "H")
        home.keyEquivalentModifierMask = [.command, .shift]
        navMenu.addItem(home)
        navMenu.addItem(.separator())
        navMenu.addItem(withTitle: "Copy Page Address", action: #selector(copyCurrentURL(_:)), keyEquivalent: "")
        navMenu.addItem(withTitle: "Open in Default Browser", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
