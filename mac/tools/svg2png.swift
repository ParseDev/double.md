// Build-time helper: rasterises an SVG to a PNG using WebKit — the same engine
// the app itself renders with, so no rsvg/inkscape/ImageMagick dependency.
//
//   svg2png <in.svg> <out.png> <canvas-px> <artwork-px>
//
// The artwork is drawn centred at `artwork-px` inside a transparent
// `canvas-px` square with a soft drop shadow, which is the macOS app-icon
// convention (824 pt of art inside a 1024 pt tile).
import Cocoa
import WebKit

let args = CommandLine.arguments
guard args.count == 5,
      let canvas = Int(args[3]), let artwork = Int(args[4]),
      let svg = try? String(contentsOfFile: args[1], encoding: .utf8)
else {
    FileHandle.standardError.write(Data("usage: svg2png <in.svg> <out.png> <canvas-px> <artwork-px>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: args[2])

let html = """
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0;background:transparent;}
  svg{display:block;width:\(artwork)px;height:\(artwork)px;}
</style></head><body>\(svg)</body></html>
"""

final class Rasteriser: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var image: NSImage?
    var done = false

    init(size: Int) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size), configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Transparent page so the tile's rounded corners stay see-through.
        // KVC because there is no public switch; this tool never ships.
        webView.setValue(false, forKey: "drawsBackground")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // One runloop turn so the SVG is laid out before the snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            webView.takeSnapshot(with: config) { image, error in
                if let error = error {
                    FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                }
                self.image = image
                self.done = true
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("load failed: \(error)\n".utf8))
        self.done = true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let rasteriser = Rasteriser(size: artwork)
rasteriser.webView.loadHTMLString(html, baseURL: nil)

let deadline = Date().addingTimeInterval(20)
while !rasteriser.done && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

guard let art = rasteriser.image else {
    FileHandle.standardError.write(Data("no image produced\n".utf8))
    exit(1)
}

// Compose onto the transparent tile.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = CGFloat(canvas - artwork) / 2
let scale = CGFloat(canvas) / 1024.0
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 20 * scale
shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
shadow.set()

art.draw(in: NSRect(x: inset, y: inset, width: CGFloat(artwork), height: CGFloat(artwork)),
         from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
