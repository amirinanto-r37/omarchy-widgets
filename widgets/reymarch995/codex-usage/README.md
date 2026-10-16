# Codex usage

This widget reads Codex session event files from `$HOME/.codex/sessions` on the
device. It does not contact a server or read authentication credentials.

## Data it reads

For each refresh, it orders `*.jsonl` files by modification time, then selects
the newest file with a line containing `rate_limits`. It parses that line's
`payload.rate_limits` object. Both `primary` and `secondary` must contain
`used_percent` and `resets_at`, with reset times expressed as Unix seconds.

The widget displays `100 - used_percent` as the remaining percentage. It
formats `resets_at` with the device's local time zone. Once a window's reset
time has passed, it displays that window as full and labels it `full`. If no
matching event or required field is available, the widget shows a waiting
state instead.

## Dependencies

The widget declares `jq`, `findutils`, `coreutils` and `grep` in its package
requirements. `jq` parses the event data, `findutils` provides `find`,
`coreutils` provides `date`, `sort`, `cut` and `tail`, and `grep` searches the
session files. `find -printf` and `date -d` are GNU options available on Arch.

To reproduce the displayed values, place a JSONL event with the described
`payload.rate_limits` shape in the session directory. The widget refreshes
once per minute.
