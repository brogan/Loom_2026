import AppKit
import WebKit

final class HelpWindowController: NSWindowController, WKNavigationDelegate {

    static let shared = HelpWindowController()

    private var webView: WKWebView!

    private init() {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Loom Help"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false

        self.webView = webView
        super.init(window: window)
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if let url = Bundle.module.url(forResource: "help", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
