import Cocoa

enum Palette {
    /// Mirrors `--background` in backend/app/frontend/entrypoints/global.css, so the
    /// window never flashes a colour the page is about to replace. The web app
    /// follows the system appearance by default (frontend hooks/use-theme.ts) and
    /// WKWebView inherits ours, so a dynamic colour keeps the two in step through
    /// light/dark switches without any extra wiring.
    static let background = NSColor(name: "SentrelBackground") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x0b / 255.0, green: 0x0b / 255.0, blue: 0x0d / 255.0, alpha: 1) // --background, .dark
            : NSColor(srgbRed: 0xfb / 255.0, green: 0xfb / 255.0, blue: 0xfd / 255.0, alpha: 1) // --background, :root
    }
}
