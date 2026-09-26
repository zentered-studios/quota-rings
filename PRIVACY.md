# Privacy policy

Quota Rings collects no data. It sends nothing to its developer and runs without analytics or crash reporting.

## What the app reads

- The Claude Code sign-in stored in your macOS Keychain under `Claude Code-credentials`. The app reads the access token only. It never changes, refreshes or copies the sign-in anywhere.

## What the app sends

- One request every 5 minutes, after wake and when you click the widget, to `https://api.anthropic.com/api/oauth/usage`, with that access token. Anthropic's privacy policy covers that request.

## What the app stores

- The latest usage numbers in `~/Library/Application Support/QuotaRings/usage.json`, so the widget can show them. The file holds percentages, reset times and the time of the last fetch. It holds no token.

## Contact

Open an issue at https://github.com/zentered-studios/quota-rings/issues.

The source code is public, so you can check every request the app makes.
