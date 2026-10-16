# Codex Quota and Tibo Reset Monitor

A seven-language OWL 6 home-screen widget for local Codex quota snapshots and public reset announcements. The interface is available in English, Simplified Chinese, Spanish, German, French, Japanese, and Korean.

## Features

- Reads five-hour and weekly quota snapshots from local Codex session records. Quota values and the local cache stay on the device.
- Shows estimated reset countdowns, awaiting-confirmation states, recent quota-window changes, and reset-time notifications.
- Reads public Tibo announcements from the documented Codex Reset JSON API. It uses only `GET /api/feed` and `GET /api/timeline`, with a project-identifying User-Agent.
- Displays Tibo announcements as returned by the API; only the widget's own interface labels are translated.
- Refreshes the public data every five minutes, observes the API's one-request-per-minute ceiling and `Retry-After`, and keeps the last valid cache when a request fails.
- Separates announced resets from credit announcements. Only a timeline event with `group: reset` and `announcement_state: announced` counts as a confirmed reset.
- Includes a calendar, selected-day records, monthly and 90-day counts, median confirmed-reset interval, source links, and a persistent language switch.

The widget displays a clickable **Data: codex-reset.com** credit next to the public data. The monitor is an unofficial community widget and is not affiliated with OpenAI, Tibo, or Codex Reset. A reset or credit announcement does not confirm that an individual Codex account has received a refill.

## Install and use

1. Add `widget.owl` to the Omarchy widget store or install it through your launcher.
2. Tap the language marker on the tile to cycle through English, Chinese, Spanish, German, French, Japanese, and Korean. In the full-screen view, choose any language directly. The selected language is saved on the device.
3. Use **My quota** to refresh the local account snapshot. Use **Check updates** to request the public monitor data; API cooldowns still apply.
4. Select a calendar date to view cached events. Calendar navigation does not trigger a quota scan or API request.

The quota scanner uses Python's standard library and reads `~/.codex/sessions`. Public event dates are grouped in Beijing time; local quota timestamps use device time. If API requests fail or the source marks its feed stale, the widget labels the data as delayed and continues to show the last valid response.

The widget requests only the data needed to render it. It does not upload local quota values, session files, or account credentials.

## Replacing the older editions

Install this unified widget, confirm that it appears on the home screen, then remove the separate English and Chinese quota widgets so you do not keep duplicate monitors.

## Update notes — 2.2.0

- Fixed **My quota** so tapping it requests a fresh local quota scan.
- Added theme-matched tap feedback and a visible refreshing state.
- Reworked compact and elongated tile layouts, including 2×2, 2×3, 3×2, 3×3, 3×4, 4×3, and 5×3, to keep content readable without clipping or overlap.

## Source

- [Codex Reset API documentation](https://codex-reset.com/developers)
- [Public feed](https://codex-reset.com/api/feed)
- [Public timeline](https://codex-reset.com/api/timeline)
