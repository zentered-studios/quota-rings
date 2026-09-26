import Foundation

/// Pure parsing for the claude.ai web API, kept free of networking so it can be tested.
///
/// Endpoints, as used by the claude.ai site itself (undocumented):
/// - `GET https://claude.ai/api/organizations` lists the account's organizations.
/// - `GET https://claude.ai/api/organizations/{uuid}/usage` returns the same shape as
///   Claude Code's `/api/oauth/usage`, which `UsageParser` reads.
enum ClaudeWebParsing {
    struct Organization: Equatable {
        let id: String
        let name: String?
        let capabilities: Set<String>
    }

    static func organizations(from data: Data) -> [Organization] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list.compactMap { obj in
            // The id goes into a URL path. Accept only UUID characters.
            guard let id = obj["uuid"] as? String, !id.isEmpty,
                  id.unicodeScalars.allSatisfy({ ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" })
            else { return nil }
            let caps = (obj["capabilities"] as? [String] ?? []).map { $0.lowercased() }
            return Organization(id: id, name: obj["name"] as? String, capabilities: Set(caps))
        }
    }

    /// The organization that carries the plan limits: one with the `chat` capability,
    /// otherwise the first that is not API-only.
    static func planOrganization(in orgs: [Organization]) -> Organization? {
        orgs.first { $0.capabilities.contains("chat") }
            ?? orgs.first { !($0.capabilities == ["api"]) }
    }

    /// Cloudflare answers blocked requests with an HTML challenge page instead of JSON.
    static func isCloudflareChallenge(status: Int, contentType: String?, body: Data) -> Bool {
        guard status == 403 || status == 503 else { return false }
        if contentType?.lowercased().contains("text/html") == true { return true }
        let head = String(decoding: body.prefix(2048), as: UTF8.self).lowercased()
        return head.contains("just a moment") || head.contains("cf-chl") || head.contains("cloudflare")
    }

    /// True for cookies that belong to claude.ai: `claude.ai`, `.claude.ai` or a subdomain.
    static func isClaudeCookieDomain(_ domain: String) -> Bool {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == "claude.ai" || host.hasSuffix(".claude.ai")
    }

    /// The `sessionKey` value from a `Set-Cookie` response, if claude.ai rotated it.
    static func renewedSessionKey(headers: [String: String], url: URL) -> String? {
        HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .first { $0.name == "sessionKey" && !$0.value.isEmpty && isClaudeCookieDomain($0.domain) }?
            .value
    }
}
