import AppKit
import WebKit

/// A window with the claude.ai login page. When claude.ai sets its `sessionKey` cookie,
/// the key goes to `SessionKeyStore` and the window closes.
///
/// The web view uses a non-persistent data store, so nothing from this login is left in
/// WebKit's shared cookies. Google sign-in may refuse to run in an embedded web view;
/// the email code login works.
@MainActor
final class SignInWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    private static var current: SignInWindowController?

    private let webView: WKWebView
    private let onSignIn: () -> Void
    private var pollTimer: Timer?
    /// The poll and a page load can both find the cookie. Only the first one counts.
    private var didSignIn = false

    static func show(onSignIn: @escaping () -> Void) {
        if let current {
            current.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = SignInWindowController(onSignIn: onSignIn)
        current = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(onSignIn: @escaping () -> Void) {
        self.onSignIn = onSignIn
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Sign in to claude.ai"
        window.contentView = webView
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        // The login finishes inside the page's own scripts, which may not trigger a navigation.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForSession() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    private func checkForSession() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.didSignIn,
                  let cookie = cookies.first(where: {
                      $0.name == "sessionKey" && ClaudeWebParsing.isClaudeCookieDomain($0.domain) && !$0.value.isEmpty
                  })
            else { return }
            self.didSignIn = true
            SessionKeyStore.save(cookie.value)
            self.finish()
            self.onSignIn()
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        pollTimer?.invalidate()
        pollTimer = nil
        webView.navigationDelegate = nil
        window?.delegate = nil
        window?.close()
        Self.current = nil
    }
}
