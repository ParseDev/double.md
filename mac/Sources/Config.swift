import Foundation

/// Everything tweakable about the shell lives here.
enum Config {
    static let appName = "Sentrel"

    /// The app opens the product, not the marketing site. `/dashboard` sits behind
    /// `authenticate_user!`, so a signed-out launch redirects straight to Devise's
    /// sign-in page and a signed-in launch lands on the dashboard — the same place
    /// `after_sign_in_path_for` sends you (backend application_controller.rb).
    private static let entryPath = "dashboard"

    /// `SENTREL_URL` overrides the origin, which is how you point a build at a
    /// local Rails server (`SENTREL_URL=http://localhost:3200 open -n Sentrel.app`).
    static var homeURL: URL {
        guard let raw = ProcessInfo.processInfo.environment["SENTREL_URL"],
              let url = URL(string: raw)
        else { return URL(string: "https://sentrel.ai/\(entryPath)")! }

        // A bare origin picks up the entry path; an explicit path is left alone.
        let hasPath = !url.path.isEmpty && url.path != "/"
        return hasPath ? url : url.appendingPathComponent(entryPath)
    }

    /// Hosts that belong to us and stay inside the app window.
    private static let appHosts = ["sentrel.ai", "localhost", "127.0.0.1"]

    /// Third parties we hand off to during OAuth and expect to come back from.
    /// These load in an in-app popup so the callback lands on our session
    /// instead of stranding the user in Safari.
    private static let authHosts = [
        "accounts.google.com",
        "google.com",
        "github.com",
        "login.microsoftonline.com",
        "login.live.com",
        "slack.com",
        "nango.dev",
        "composio.dev",
        "stripe.com",
        "auth0.com",
        "okta.com",
        "atlassian.com",
        "notion.so",
        "hubspot.com",
        "salesforce.com",
        "zoom.us",
        "linear.app",
    ]

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// WKWebView sends no `Version/… Safari/…` token by default, and the Rails
    /// `allow_browser versions: :modern` gate answers 406 to anything it cannot
    /// recognise as a current browser. Report the Safari that is actually
    /// installed — it is the same WebKit doing the rendering — then our own
    /// product, so server-side analytics can still tell desktop from web.
    static var userAgentSuffix: String {
        "Version/\(installedSafariVersion) Safari/605.1.15 SentrelDesktop/\(appVersion)"
    }

    private static var installedSafariVersion: String {
        let fallback = "18.0"
        guard let safari = Bundle(path: "/Applications/Safari.app"),
              let version = safari.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty
        else { return fallback }
        return version
    }

    static func isAppHost(_ url: URL) -> Bool { matches(url, appHosts) }
    static func isAuthHost(_ url: URL) -> Bool { matches(url, authHosts) }

    /// True for anything we are willing to render ourselves.
    static func staysInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "https" || scheme == "http" else { return false }
        return isAppHost(url) || isAuthHost(url)
    }

    private static func matches(_ url: URL, _ hosts: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
