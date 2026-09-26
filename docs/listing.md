# Listing copy

Copy for the download page, GitHub release and any directory listing. Character limits follow App Store Connect in case the app ever ships there.

## Name (30)

Quota Rings

## Subtitle (30)

Plan limits on your desktop

## Promotional text (170)

See your session, weekly and per-model limits before you hit them. A desktop widget and menu bar item that update every 5 minutes.

## Description

Quota Rings shows your coding assistant plan limits on your Mac desktop.

- Session, weekly and per-model limits as rings, each with its reset countdown.
- Small and medium desktop widgets, plus a compact menu bar item.
- Numbers turn red near the limit.
- Updates every 5 minutes, after wake, and when you click the widget.
- Clear status when you are signed out, offline or your sign-in expired. Old numbers dim instead of pretending to be current.

Requirements: macOS 14 or later, and Claude Code signed in with a Pro or Max plan. Quota Rings reads the sign-in that Claude Code already stores on your Mac. It never asks for a password and never changes that sign-in.

Quota Rings is an independent app. It is not made, endorsed or supported by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## Keywords (100)

usage,quota,limits,widget,menu bar,rings,AI,coding,plan,developer,tokens,rate limit

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
