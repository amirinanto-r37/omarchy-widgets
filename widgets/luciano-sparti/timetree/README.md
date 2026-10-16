# TimeTree Widget

A shared calendar widget for TimeTree on omalauncher.

## Features

- **Monthly Calendar Grid**: Full monthly view with Sunday in red, Saturday in cyan, and today highlighted in TimeTree green (`#10b981`).
- **Event Indicators**: Color-coded dots under dates with scheduled events.
- **Interactive Day Selection**: Tap any date to view its daily agenda in the side panel.
- **Month Navigation**: Quickly browse previous/next months or jump back to today.
- **Deep Linking**: Direct tap to open the TimeTree Android app (`works.jubilee.timetree`).
- **Android Notifications**: Intercepts active TimeTree notifications to display reminder banners.
- **Full-Screen Screen View**: Expanded month calendar and detailed day schedule.

## Event Data Format

Events are read from `~/.config/timetree/events.json`. Each event is a JSON object with the following fields:

- `id`: Unique identifier (string or number)
- `date`: Date in `YYYY-MM-DD` format
- `time`: Time in `HH:MM` or time range (e.g. `"14:00"` or `"19:00 - 21:00"`)
- `title`: Event title (e.g. `"Family Dinner"`)
- `calendar`: Calendar name or category (e.g. `"Family"`)
- `color`: Hex color code for the event indicator dot (e.g. `"#10b981"`)

> **Note:** Each event object must be on its own line in the JSON array, because the parser reads line-by-line to extract dates and colors efficiently:

```json
[
  {"id": "1", "date": "2026-10-12", "time": "18:00", "title": "Family Dinner", "calendar": "Family", "color": "#10b981"},
  {"id": "2", "date": "2026-10-15", "time": "14:30", "title": "Doctor Appointment", "calendar": "Personal", "color": "#3b82f6"}
]
```

Tap **Edit Events** in the full-screen view to open `~/.config/timetree/events.json` in your terminal editor.
