# Listing copy

Copy for the download page, GitHub release and any directory listing. Character limits follow App Store Connect in case the app ever ships there.

## Name (30)

Quota Rings

## Subtitle (30)

Plan limits on your desktop

## Promotional text (170)

See your Claude and Codex limits before you hit them. A desktop widget and menu bar item that update every 5 minutes.

## Description

Quota Rings shows your coding assistant plan limits on your Mac desktop.

- Claude and Codex side by side: session, weekly and per-model limits as bars, each with its reset countdown.
- Small and medium desktop widgets, plus a compact menu bar item.
- Bars turn amber at 80% and red at 95%.
- Updates every 5 minutes, after wake, and when you click the widget.
- Clear status when you are signed out, offline or your sign-in expired. Old numbers dim instead of pretending to be current.

Requirements: macOS 14 or later and a Claude Pro or Max plan. Quota Rings either reads the sign-in that Claude Code already stores on your Mac, or you sign in to claude.ai once in the app. It never changes Claude Code's sign-in. Codex usage is optional and comes from the logs Codex CLI writes on your Mac, with no network request.

Quota Rings is an independent app. It is not made, endorsed or supported by Anthropic or OpenAI. Claude and Claude Code are trademarks of Anthropic.

## Keywords (100)

usage,quota,limits,widget,menu bar,codex,AI,coding,plan,developer,tokens,rate limit

## Category

Developer Tools

## Release notes for 0.1.0

First release. Desktop widget in small and medium sizes, menu bar item, and status for signed-out, expired, offline and no-plan states.

## Screenshots

`docs/screenshots/`, 2880x1800 PNG. Regenerate with `./scripts/screenshots.sh`.

| File | Headline |
| --- | --- |
| `01-at-a-glance.png` | Your plan limits, at a glance. |
| `02-know-when-it-resets.png` | See the wall before you hit it. |
| `03-menu-bar.png` | Also in your menu bar. |
| `04-always-honest.png` | Clear about what it knows. |

`03-menu-bar.png` shows a drawn menu bar and menu, not a screen capture.

## Open questions

- Support URL: https://github.com/zentered-studios/quota-rings/issues. A marketing URL is not set up.
- The model label in the screenshots ("Fable") is the name the usage API returns. It is an Anthropic model name. Replace the sample label in `Tools/Screenshots/main.swift` if the listing must avoid it.
