# Claude Usage widget

A macOS desktop widget that shows Claude plan usage. It lists the session limit, the weekly limit and each model-scoped weekly limit such as Fable.

## How it works

- `Claude Usage.app` runs in the menu bar and shows `session% · week%`.
- Every 5 minutes it reads Claude Code's OAuth token from the Keychain item `Claude Code-credentials` and calls `GET https://api.anthropic.com/api/oauth/usage`. Claude Code's `/usage` reads the same endpoint.
- It writes the result to `~/Library/Application Support/ClaudeUsageWidget/usage.json` and reloads the widget.
- The widget is sandboxed. It has read-only access to that one folder and no network or Keychain access.

The app never refreshes the token. Refreshing would rotate the refresh token Claude Code stores and sign Claude Code out. When the token expires, the widget shows a warning until you run `claude` once.

`/api/oauth/usage` is not a documented public API. Its response shape can change.

## Requirements

- macOS 14 or later
- Xcode and `xcodegen` (`brew install xcodegen`)
- Claude Code logged in with a Pro or Max plan

## Install

```sh
./scripts/install.sh
```

This builds Release, copies the app to `~/Applications/Claude Usage.app` and launches it. Then:

1. Right-click the desktop, choose **Edit Widgets**, search for **Claude Usage** and add the small or medium size.
2. Turn on **Open at Login** in the menu bar menu so the widget keeps updating.

## Test

```sh
./scripts/test.sh
```

## Signing

The project signs ad hoc (`CODE_SIGN_IDENTITY = "-"`) so it builds without an Apple developer team. To sign with a team, set `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE: Automatic` in `project.yml` and run `xcodegen generate`.
