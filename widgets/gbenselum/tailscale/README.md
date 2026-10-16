# tailscale

Shows the Tailscale status and the devices on your tailnet.

- Header: the Tailscale logo with a green/red dot and `connected`/`disconnected`.
- Connected: the tailnet name and one row per device, each with an `ip` button
  and, when the hostname resolved, a `host` button that copies it to the
  clipboard. If only this device is online, a note says so.
- When Tailscale rebuilds the tunnel (it renames the `tun` interface and
  reinstalls the device routes), the routes disappear for a moment. The header
  then says `reconnecting…` and the last known device list stays, instead of
  dropping to the "only this device is online" note. The list is kept across
  restarts.
- Disconnected: a button that opens the Tailscale app.

## Requirements

- **Tailscale installed and configured on the device, with the VPN running in
  the Tailscale Android app.** This widget reads the tunnel Tailscale sets up on
  Android; it cannot start or stop the VPN itself, so the `open tailscale`
  button opens the app instead of toggling the connection.
- MagicDNS enabled for device hostnames (without it, rows show IPs only).
- `iproute2` and `bind` (declared in `requires`). Names are resolved through
  the guest resolver first, falling back to asking MagicDNS (100.100.100.100)
  directly, so hostnames work even before the launcher publishes the phone's
  real network DNS (omalauncher#20).
