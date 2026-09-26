import Foundation

/// Refuses every HTTP redirect. The fetchers put credentials in hand-set headers
/// (`Authorization`, `Cookie`), which URLSession would otherwise carry to the redirect target.
/// A redirect then surfaces as its 3xx response and fails as an HTTP error.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension URLSession {
    /// Ephemeral, no shared cookies, no redirects.
    static func credentialSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
}
