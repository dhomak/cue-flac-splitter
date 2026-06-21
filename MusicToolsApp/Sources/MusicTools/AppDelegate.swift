import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {

    private var window: NSWindow!
    private var webView: WKWebView!
    private let server = ServerController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        showSplash()

        server.start(
            onReady: { [weak self] in
                guard let self = self else { return }
                self.webView.load(URLRequest(url: self.server.baseURL))
            },
            onFailure: { [weak self] message in
                self?.showError(message)
            }
        )

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stopAndWait()
    }

    // MARK: - UI

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        // Bridge: JS posts to window.webkit.messageHandlers.musicTools
        config.userContentController.add(self, name: "musicTools")

        let frame = NSRect(x: 0, y: 0, width: 1180, height: 800)
        webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true  // right-click → Inspect Element for beta debugging
        }

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Music Tools"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.setFrameAutosaveName("MusicToolsMainWindow")
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
    }

    private func showSplash() {
        // Inline splash matching the app's palette while the server warms up.
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          html,body{height:100%;margin:0;background:#050508;color:#c0c0e0;
            font-family:-apple-system,'Space Mono',monospace;
            display:flex;align-items:center;justify-content:center;flex-direction:column;gap:18px}
          .ring{width:42px;height:42px;border:3px solid #15152a;border-top-color:#00e8cc;
            border-radius:50%;animation:spin .8s linear infinite}
          @keyframes spin{to{transform:rotate(360deg)}}
          .t{letter-spacing:.18em;text-transform:uppercase;font-size:13px;color:#606088}
          .a{color:#00e8cc}
        </style></head><body>
          <div class="ring"></div>
          <div class="t">starting <span class="a">music-tools</span>…</div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showError(_ message: String) {
        let safe = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          html,body{height:100%;margin:0;background:#050508;color:#c0c0e0;
            font-family:-apple-system,'Space Mono',monospace;
            display:flex;align-items:center;justify-content:center;padding:40px}
          .box{max-width:620px}
          h1{color:#ff3060;font-size:15px;letter-spacing:.1em;text-transform:uppercase;margin:0 0 14px}
          pre{white-space:pre-wrap;font-size:13px;line-height:1.5;color:#909}
          pre{color:#8a8ab0;background:#0b0b18;border:1px solid #1e1e38;border-radius:8px;padding:14px}
        </style></head><body>
          <div class="box"><h1>Server failed to start</h1><pre>\(safe)</pre></div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - JS → native bridge (optional folder picker)

    // Wire a browse button in index.html to a real macOS folder picker:
    //   window.webkit.messageHandlers.musicTools.postMessage(
    //     { action: "pickFolder", target: "cue-path" });
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard
            let body = message.body as? [String: Any],
            body["action"] as? String == "pickFolder",
            let target = body["target"] as? String
        else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder"

        // Open at the folder already typed in the field, else the Music folder.
        if let current = body["current"] as? String, !current.isEmpty {
            let expanded = (current as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                panel.directoryURL = URL(fileURLWithPath: expanded)
            }
        } else if let music = FileManager.default
            .urls(for: .musicDirectory, in: .userDomainMask).first {
            panel.directoryURL = music
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let escaped = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function(){var el=document.getElementById('\(target)');
            if(el){el.value='\(escaped)';
            el.dispatchEvent(new Event('input',{bubbles:true}));}})();
            """
            self?.webView.evaluateJavaScript(js)
        }
    }

    // Open external (non-localhost) links in the default browser instead of
    // navigating the app window away from the tool UI.
    func webView(_ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let host = url.host,
           host != "127.0.0.1", host != "localhost",
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
