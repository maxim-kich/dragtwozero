import AppKit
import WebKit

// Render the editable SVG with WebKit so filters and transparent corners survive.
final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    let destination: URL
    init(source: URL, destination: URL) throws {
        self.destination = destination
        super.init()
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        let svg = try String(contentsOf: source)
        web.loadHTMLString("<html><head><style>html,body{margin:0;width:1024px;height:1024px;background:transparent}svg{display:block}</style></head><body>\(svg)</body></html>", baseURL: source.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
            config.snapshotWidth = 1024
            self.web.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fputs("Icon rendering failed: \(String(describing: error))\n", stderr); exit(1)
                }
                do { try png.write(to: self.destination); exit(0) }
                catch { fputs("\(error)\n", stderr); exit(1) }
            }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = try Renderer(source: URL(fileURLWithPath: CommandLine.arguments[1]), destination: URL(fileURLWithPath: CommandLine.arguments[2]))
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fputs("Icon render timed out\n", stderr); exit(1) }
app.run()
