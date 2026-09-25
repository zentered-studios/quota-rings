import Foundation

/// Reads Claude Code's OAuth token from the Keychain and fetches plan usage.
///
/// The token is only read, never refreshed. Refreshing would rotate the refresh token
/// that Claude Code stores and sign Claude Code out. When the token expires, running
/// `claude` refreshes it and the next poll picks it up.
enum UsageFetcher {
    enum FetchError: Error, LocalizedError {
        case noCredentials
        case tokenExpired
        case unauthorized
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noCredentials: return "No Claude Code login found. Run `claude` and log in."
            case .tokenExpired, .unauthorized: return "Token expired. Run `claude` once to refresh it."
            case .http(let code): return "Usage request failed (HTTP \(code))"
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws -> [UsageLimit] {
        let token = try readToken()
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-usage-widget/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try UsageParser.parse(data)
        case 401, 403: throw FetchError.unauthorized
        default: throw FetchError.http(status)
        }
    }

    /// Claude Code stores its credentials with `/usr/bin/security`, so that binary is on the
    /// item's access list and reading through it does not trigger a Keychain prompt.
    private static func readToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FetchError.noCredentials }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw FetchError.noCredentials }

        if let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expiresMs / 1000) < Date() {
            throw FetchError.tokenExpired
        }
        return token
    }
}
