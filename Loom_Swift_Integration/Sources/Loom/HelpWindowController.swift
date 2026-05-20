import AppKit
import WebKit

final class HelpWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler {

    static let shared = HelpWindowController()

    private var webView: WKWebView!

    private init() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(PrintMessageProxy(), name: "printHelp")
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

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "printHelp" else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36; info.bottomMargin = 36
        info.leftMargin = 36; info.rightMargin = 36
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let win = window {
            op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }
}

// WKUserContentController retains its message handlers strongly, which would
// create a retain cycle for a singleton. A lightweight proxy breaks the cycle.
private final class PrintMessageProxy: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        HelpWindowController.shared.userContentController(userContentController,
                                                          didReceive: message)
    }
}
