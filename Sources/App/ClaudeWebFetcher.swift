import Foundation
import Security

/// Fetches plan usage from claude.ai with a session the user signed in to inside Quota Rings.
///
/// This path needs no access to Claude Code, so it also works inside the app sandbox.
enum ClaudeWebFetcher {
    enum FetchError: Error, LocalizedError {
        case notSignedIn
        case sessionExpired
        case noOrganization
        case cloudflare
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "No claude.ai session saved"
            case .sessionExpired: return "claude.ai rejected the saved session"
            case .noOrganization: return "No claude.ai organization with plan limits"
            case .cloudflare: return "claude.ai returned a Cloudflare challenge. A VPN can cause this."
            case .http(let code): return "claude.ai request failed (HTTP \(code))"
            }
        }
    }

    private static let base = URL(string: "https://claude.ai/api/")!

    /// Requests carry the cookie by hand, so no shared cookie store is involved.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func fetch() async throws -> [UsageLimit] {
        let orgData = try await get("organizations")
        guard let org = ClaudeWebParsing.planOrganization(in: ClaudeWebParsing.organizations(from: orgData)) else {
            throw FetchError.noOrganization
        }
        let usageData = try await get("organizations/\(org.id)/usage")
        return try UsageParser.parse(usageData)
    }

    private static func get(_ path: String) async throws -> Data {
        guard let key = SessionKeyStore.load() else { throw FetchError.notSignedIn }
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("quota-rings/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.http(0) }

        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let k = pair.key as? String, let v = pair.value as? String { result[k] = v }
        }
        if let renewed = ClaudeWebParsing.renewedSessionKey(headers: headers, url: url), renewed != key {
            SessionKeyStore.save(renewed)
        }

        switch http.statusCode {
        case 200:
            return data
        case _ where ClaudeWebParsing.isCloudflareChallenge(
            status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), body: data):
            throw FetchError.cloudflare
        case 401, 403:
            throw FetchError.sessionExpired
        default:
            throw FetchError.http(http.statusCode)
        }
    }
}

/// The claude.ai session key, in Quota Rings' own Keychain item.
enum SessionKeyStore {
    private static let service = "com.zentered.quotarings.claude-ai"
    private static let account = "sessionKey"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let data = Data(key.utf8)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
