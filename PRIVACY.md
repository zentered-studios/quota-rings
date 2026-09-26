# Privacy policy

Quota Rings collects no data. It sends nothing to its developer and runs without analytics or crash reporting.

Quota Rings has two data sources. You pick one in the menu bar menu.

## Claude Code sign-in

- **Reads:** the Claude Code sign-in stored in your macOS Keychain under `Claude Code-credentials`. The app reads the access token only. It never changes, refreshes or copies that sign-in.
- **Sends:** one request every 5 minutes, after wake and when you click the widget, to `https://api.anthropic.com/api/oauth/usage`, with that access token.

## claude.ai sign-in

- **Reads:** the `sessionKey` cookie that claude.ai sets when you sign in through the app's login window. The window uses a private web view store, so the rest of that login is discarded when it closes.
- **Stores:** that session key in the app's own Keychain item, `com.zentered.quotarings.claude-ai`, readable on this Mac only. When claude.ai issues a new key, the app replaces the old one. **Sign Out of claude.ai** in the menu deletes it.
- **Sends:** the same schedule of requests to `https://claude.ai/api/organizations` and `https://claude.ai/api/organizations/{id}/usage`, with that session key.

Anthropic's privacy policy covers the requests to Anthropic's servers.

## What the app stores on disk

- The latest usage numbers in `~/Library/Application Support/QuotaRings/usage.json`, so the widget can show them. The file holds percentages, reset times, the time of the last fetch and the last error message. It holds no token or session key.

## Contact

Open an issue at https://github.com/zentered-studios/quota-rings/issues.

The source code is public, so you can check every request the app makes.
