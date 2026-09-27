# Privacy policy

Quota Rings collects no data. It sends nothing to its developer and runs without analytics or crash reporting.

Quota Rings reads Claude usage through Claude Code's sign-in, and Codex usage from Codex's logs when Codex is installed.

## Claude Code sign-in

- **Reads:** the Claude Code sign-in stored in your macOS Keychain under `Claude Code-credentials`. The app reads the access token only. It never changes, refreshes or copies that sign-in.
- **Sends:** one request every 5 minutes, after wake and when you click the widget, to `https://api.anthropic.com/api/oauth/usage`, with that access token.

Earlier builds could sign in to claude.ai and kept a session key in the Keychain item `com.zentered.quotarings.claude-ai`. The current app deletes that item on launch and stores no Claude credentials.

## Codex

- **Reads:** the newest Codex session logs in `~/.codex/sessions/`, up to 5 files per refresh. The app keeps only the plan limit fields (`rate_limits`) and ignores the rest of each log, including your prompts and code. It never reads `~/.codex/auth.json` or any Codex token.
- **Sends:** nothing. Codex usage makes no network request.

Anthropic's privacy policy covers the requests to Anthropic's servers.

## What the app stores on disk

- The latest Claude and Codex usage numbers in `~/Library/Application Support/QuotaRings/usage.json`, so the widget can show them. The file holds percentages, reset times, the time of the last fetch and the last error message. It holds no token or session key.

## Contact

Open an issue at https://github.com/zentered-studios/quota-rings/issues.

The source code is public, so you can check every request the app makes.
