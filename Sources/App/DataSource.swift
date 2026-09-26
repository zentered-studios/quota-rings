import Foundation

/// Where usage comes from.
enum DataSource: String, CaseIterable {
    /// Claude Code's sign-in in the Keychain. Needs no setup, but only works outside the sandbox.
    case claudeCode
    /// A claude.ai session the user signs in to inside Quota Rings.
    case claudeAI

    var menuTitle: String {
        switch self {
        case .claudeCode: return "Claude Code sign-in"
        case .claudeAI: return "claude.ai sign-in"
        }
    }

    func fetch() async throws -> [UsageLimit] {
        switch self {
        case .claudeCode: return try await UsageFetcher.fetch()
        case .claudeAI: return try await ClaudeWebFetcher.fetch()
        }
    }

    func status(for error: Error) -> UsageStatus {
        switch (self, error) {
        case (.claudeAI, ClaudeWebFetcher.FetchError.notSignedIn): return .notSignedIn
        case (.claudeAI, ClaudeWebFetcher.FetchError.sessionExpired): return .expired
        case (.claudeAI, ClaudeWebFetcher.FetchError.noOrganization): return .noPlan
        default: return UsageFetcher.status(for: error)
        }
    }

    /// Next step for the widget when it differs from the Claude Code wording.
    func detail(for status: UsageStatus, error: Error) -> String? {
        guard self == .claudeAI else { return nil }
        if case ClaudeWebFetcher.FetchError.cloudflare = error { return "claude.ai blocked the request. Try without a VPN." }
        switch status {
        case .notSignedIn: return "Sign in to claude.ai from the menu bar."
        case .expired: return "Sign in to claude.ai again from the menu bar."
        default: return nil
        }
    }
}
