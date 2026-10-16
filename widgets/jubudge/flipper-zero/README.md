# Flipper Zero

A Flipper Zero's live screen and buttons on the home screen. The tile shows the 128x64 display in
its orange backlight, with a D-pad, OK and Back next to it (a row of keys when the tile is narrow),
and the Flipper's name and battery underneath. Tap the screen for a full-screen view with a bigger
display, and to set which computer to reach.

## How it works

Android doesn't let the phone's Linux use Bluetooth or USB, so the Flipper plugs into a computer
over USB. There, `flipper_bridge.py` (below) opens an RPC session on the Flipper's serial port, the
protocol qFlipper and the mobile app use, and serves its screen and buttons on that computer's
`127.0.0.1:8765`. The widget reaches it over ssh:

- A small feeder process streams frames from the bridge into `~/.cache/owl-flipper/frame.json`,
  which the widget reads. It runs while the tile is on screen and quits 45 s after it isn't.
- A button press runs `curl` on the computer over the feeder's shared ssh connection, so it takes
  well under a tenth of a second.
- The bridge wants a token, which never leaves the computer: each command reads it there from
  `~/.config/flipper-bridge/token`.

## Setup

1. **On the computer the Flipper is plugged into** (Linux or macOS with Python 3), save
   `flipper_bridge.py` from below as `~/.local/share/flipper-bridge/flipper_bridge.py`. On Linux,
   run it as a user service with the unit below, saved as
   `~/.config/systemd/user/flipper-bridge.service`:

   ```sh
   systemctl --user enable --now flipper-bridge
   loginctl enable-linger "$USER"     # keeps it running while you're logged out
   ```

   Or start it by hand with `python3 flipper_bridge.py`. It finds the Flipper by itself, prints
   `connected to ...`, and creates the token on its first run. On Linux, your user needs access
   to `/dev/ttyACM0`. A desktop session usually grants that; otherwise join the `uucp` group
   (or `dialout`). Close qFlipper first, since only one program can hold the port.

2. **On the phone**, make sure `ssh <host>` works from the phone's Linux with a key and no
   password prompt, using a host from `~/.ssh/config` or `user@address`.

3. Tap the widget's screen, enter that ssh host and tap **connect**. It's kept in
   `~/.config/owl-flipper/host`.

Long-press belongs to the home screen, so tap **long** to make the next button a long press
(holding Back exits apps, for example).

The bridge listens on localhost only. Anyone who can press the Flipper's buttons can run its
Bad USB scripts on the computer it's plugged into, which is why the bridge wants the token too.
`python3 flipper_bridge.py --demo` serves a fake Flipper, for trying the widget without one.

<details>
<summary><code>flipper-bridge.service</code></summary>

```ini
[Unit]
Description=Flipper Zero screen and buttons over HTTP on localhost (for the omalauncher widget)

[Service]
ExecStart=/usr/bin/python3 -u %h/.local/share/flipper-bridge/flipper_bridge.py --listen 127.0.0.1:8765
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

</details>

<details>
<summary><code>flipper_bridge.py</code></summary>

```python
#!/usr/bin/env python3
"""flipper-bridge: a USB-connected Flipper Zero's screen and buttons over HTTP.

Run it on the computer the Flipper is plugged into. It opens an RPC session on
the Flipper's USB serial port (the protocol qFlipper and the mobile app use),
streams the 128x64 screen and sends button presses. Standard library only
(pyserial is used if it's installed; on Windows it's needed, with --port COM3).

    python3 flipper_bridge.py                 # finds the Flipper, serves on 127.0.0.1:8765
    python3 flipper_bridge.py --port /dev/ttyACM0 --listen 0.0.0.0:8765
    python3 flipper_bridge.py --demo          # a fake Flipper, for testing

It listens on localhost only by default; the omalauncher widget reaches it over
ssh. Every request needs ?token=..., kept in ~/.config/flipper-bridge/token
(anyone who can press buttons can run BadUSB scripts on this computer).
--no-token turns that off.

    GET /stream   one JSON line per screen change, and every 5 s regardless;
                  ?split=2 sends each frame as two lines of 32 rows ({part: 0|1}),
                  for readers that cap line length (omalauncher's is about 8 KB)
    GET /state    the same JSON, once
    GET /input?key=up|down|left|right|ok|back&type=short|long
"""

import argparse
import glob
import json
import os
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

W, H = 128, 64
KEYS = {"up": 0, "down": 1, "right": 2, "left": 3, "ok": 4, "back": 5}
PRESS, RELEASE, SHORT, LONG = 0, 1, 2, 3

# Field numbers of PB_Main's content, from flipperzero-protobuf's flipper.proto.
F_DEVICE_INFO_REQ, F_DEVICE_INFO_RESP = 32, 33
F_POWER_INFO_REQ, F_POWER_INFO_RESP = 44, 45
F_SCREEN_STREAM_START, F_SCREEN_FRAME, F_INPUT_EVENT = 20, 22, 23


# --- protobuf, just enough of it ---------------------------------------------

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def read_varint(buf, i):
    n = shift = 0
    while True:
        if i >= len(buf):
            raise IndexError
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return n, i


def field_varint(num, n):
    return varint(num << 3) + varint(n)


def field_bytes(num, data):
    return varint(num << 3 | 2) + varint(len(data)) + data


def fields(buf):
    """Yields (field number, value) for varint and length-delimited fields."""
    i = 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, i = read_varint(buf, i)
        elif wire == 2:
            ln, i = read_varint(buf, i)
            val, i = buf[i:i + ln], i + ln
        elif wire == 5:
            val, i = buf[i:i + 4], i + 4
        elif wire == 1:
            val, i = buf[i:i + 8], i + 8
        else:
            raise ValueError("wire type %d" % wire)
        yield num, val


# --- serial port ---------------------------------------------------------------

class Port:
    """A raw serial port: pyserial if it's installed, else termios (Linux, macOS)."""

    def __init__(self, path):
        self.path = path
        try:
            import serial
            self.ser = serial.Serial(path, 230400, timeout=0.2)
            self.fd = None
        except ImportError:
            import termios
            import tty
            self.ser = None
            self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
            tty.setraw(self.fd)
            attrs = termios.tcgetattr(self.fd)
            attrs[6][termios.VMIN], attrs[6][termios.VTIME] = 0, 2  # reads wait up to 0.2 s
            termios.tcsetattr(self.fd, termios.TCSANOW, attrs)

    def read(self):
        if self.ser:
            return self.ser.read(self.ser.in_waiting or 1)
        return os.read(self.fd, 4096)

    def write(self, data):
        if self.ser:
            self.ser.write(data)
            return
        while data:
            data = data[os.write(self.fd, data):]

    def close(self):
        try:
            self.ser.close() if self.ser else os.close(self.fd)
        except OSError:
            pass


def find_port():
    pats = ["/dev/serial/by-id/*Flipper*", "/dev/cu.usbmodemflip*", "/dev/tty.usbmodemflip*"]
    for pat in pats:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[0]
    try:
        from serial.tools import list_ports
        for p in list_ports.comports():
            if p.vid == 0x0483 and p.pid == 0x5740:  # Flipper Zero's USB ids
                return p.device
    except ImportError:
        pass
    return None


# --- shared state ----------------------------------------------------------------

class State:
    def __init__(self):
        self.cond = threading.Condition()
        self.seq = 0
        self.connected = False
        self.error = "starting"
        self.info = {}
        self.power = {}
        self.rows = None

    def update(self, **kw):
        with self.cond:
            for k, v in kw.items():
                setattr(self, k, v)
            self.seq += 1
            self.cond.notify_all()

    def snapshot(self):
        with self.cond:
            level = self.power.get("charge.level")
            charge = self.power.get("charge.state", "")
            return {
                "ok": True,
                "connected": self.connected,
                "error": None if self.connected else self.error,
                "name": self.info.get("hardware.name"),
                "fw": self.info.get("firmware.version"),
                "battery": int(level) if level and level.isdigit() else None,
                "charging": charge in ("charging", "charged"),
                "rows": self.rows,
                "seq": self.seq,
            }


def decode_frame(data, orientation):
    """1024 bytes, 8 rows of 8-pixel-tall columns (u8g2 pages), to 64 strings of '.' and 'x'."""
    rows = []
    for y in range(H):
        base, bit = (y >> 3) * W, 1 << (y & 7)
        rows.append("".join("x" if data[base + x] & bit else "." for x in range(W)))
    if orientation in (1, 3):  # flipped: left-handed mode
        rows = [r[::-1] for r in reversed(rows)]
    return rows


# --- the real Flipper --------------------------------------------------------------

class Flipper:
    def __init__(self, state, port_path):
        self.state = state
        self.port_path = port_path
        self.port = None
        self.lock = threading.Lock()
        self.cmd_id = 0

    def send(self, field, payload=b""):
        with self.lock:
            if not self.port:
                raise IOError("flipper not connected")
            self.cmd_id += 1
            main = field_varint(1, self.cmd_id) + field_bytes(field, payload)
            self.port.write(varint(len(main)) + main)

    def press(self, key, kind):
        types = [PRESS, LONG if kind == "long" else SHORT, RELEASE]
        for t in types:
            self.send(F_INPUT_EVENT, field_varint(1, KEYS[key]) + field_varint(2, t))

    def run(self):
        while True:
            path = self.port_path or find_port()
            if not path:
                self.state.update(connected=False, error="flipper not found (plugged in over USB?)")
                time.sleep(2)
                continue
            try:
                self.session(path)
            except (OSError, IOError, ValueError, IndexError) as e:
                self.state.update(connected=False, error="flipper disconnected: %s" % e)
            finally:
                with self.lock:
                    if self.port:
                        self.port.close()
                    self.port = None
            time.sleep(2)

    def session(self, path):
        port = Port(path)
        # Leave whatever was running, wait for the CLI prompt, then switch to RPC.
        port.write(b"\x03\r")
        self.read_until(port, b">: ", 3)
        port.write(b"start_rpc_session\r")
        self.read_until(port, b"start_rpc_session\r\n", 3)
        with self.lock:
            self.port, self.cmd_id = port, 0
        info, power = {}, {}
        self.state.update(connected=True, error=None, info=info, power=power)
        self.send(F_DEVICE_INFO_REQ)
        self.send(F_POWER_INFO_REQ)
        self.send(F_SCREEN_STREAM_START)
        print("connected to %s" % path, flush=True)

        buf = bytearray()
        last_power = time.time()
        while True:
            chunk = port.read()
            if chunk:
                buf += chunk
            elif not os.path.exists(path) and not path.upper().startswith("COM"):
                raise IOError("port went away")
            while True:
                try:
                    ln, i = read_varint(buf, 0)
                except IndexError:
                    break
                if len(buf) < i + ln:
                    break
                msg, buf = bytes(buf[i:i + ln]), buf[i + ln:]
                self.handle(msg, info, power)
            if time.time() - last_power > 10:
                last_power = time.time()
                self.send(F_POWER_INFO_REQ)  # battery, and notices a dead link

    @staticmethod
    def read_until(port, marker, timeout):
        got, end = b"", time.time() + timeout
        while marker not in got:
            if time.time() > end:
                raise IOError("no answer from the Flipper's CLI (is qFlipper open?)")
            got += port.read()
        return got

    def handle(self, msg, info, power):
        for num, val in fields(msg):
            if num == F_SCREEN_FRAME:
                parts = dict(fields(val))
                data = parts.get(1, b"")
                if len(data) == W * H // 8:
                    rows = decode_frame(data, parts.get(2, 0))
                    if rows != self.state.rows:  # the Flipper resends unchanged frames
                        self.state.update(rows=rows)
            elif num in (F_DEVICE_INFO_RESP, F_POWER_INFO_RESP):
                parts = dict(fields(val))
                key = parts.get(1, b"").decode(errors="replace").replace("_", ".")
                value = parts.get(2, b"").decode(errors="replace")
                (info if num == F_DEVICE_INFO_RESP else power)[key] = value
                self.state.update()


# --- a fake one, for trying the widget without a Flipper -----------------------------

FONT = {  # 5x7, rows top to bottom
    "A": ".###. #...# #...# ##### #...# #...# #...#", "B": "####. #...# #...# ####. #...# #...# ####.",
    "C": ".###. #...# #.... #.... #.... #...# .###.", "D": "####. #...# #...# #...# #...# #...# ####.",
    "E": "##### #.... #.... ####. #.... #.... #####", "F": "##### #.... #.... ####. #.... #.... #....",
    "G": ".###. #...# #.... #.### #...# #...# .####", "H": "#...# #...# #...# ##### #...# #...# #...#",
    "I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.", "J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
    "K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#", "L": "#.... #.... #.... #.... #.... #.... #####",
    "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#", "N": "#...# #...# ##..# #.#.# #..## #...# #...#",
    "O": ".###. #...# #...# #...# #...# #...# .###.", "P": "####. #...# #...# ####. #.... #.... #....",
    "Q": ".###. #...# #...# #...# #.#.# #..#. .##.#", "R": "####. #...# #...# ####. #.#.. #..#. #...#",
    "S": ".#### #.... #.... .###. ....# ....# ####.", "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    "U": "#...# #...# #...# #...# #...# #...# .###.", "V": "#...# #...# #...# #...# #...# .#.#. ..#..",
    "W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.", "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
    "Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..", "Z": "##### ....# ...#. ..#.. .#... #.... #####",
    "0": ".###. #...# #..## #.#.# ##..# #...# .###.", "1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
    "2": ".###. #...# ....# ...#. ..#.. .#... #####", "3": "##### ...#. ..#.. ...#. ....# #...# .###.",
    "4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.", "5": "##### #.... ####. ....# ....# #...# .###.",
    "6": "..##. .#... #.... ####. #...# #...# .###.", "7": "##### ....# ...#. ..#.. .#... .#... .#...",
    "8": ".###. #...# #...# .###. #...# #...# .###.", "9": ".###. #...# #...# .#### ....# ...#. .##..",
    "-": "..... ..... ..... ##### ..... ..... .....", ".": "..... ..... ..... ..... ..... .##.. .##..",
    ":": "..... .##.. .##.. ..... .##.. .##.. .....", "%": "##... ##..# ...#. ..#.. .#... #..## ...##",
    "/": "..... ....# ...#. ..#.. .#... #.... .....", ">": ".#... ..#.. ...#. ....# ...#. ..#.. .#...",
    " ": "..... ..... ..... ..... ..... ..... .....",
}


class Demo:
    ITEMS = ["SUB-GHZ", "125 KHZ RFID", "NFC", "INFRARED", "GPIO", "IBUTTON",
             "BAD USB", "U2F", "APPS", "SETTINGS"]

    def __init__(self, state):
        self.state = state
        self.view, self.cursor, self.top, self.last = "desktop", 0, 0, ""
        state.update(connected=True, error=None, power={"charge.level": "87", "charge.state": "discharging"},
                     info={"hardware.name": "Demo", "firmware.version": "1.3.4"})

    def press(self, key, kind):
        self.last = "%s %s" % (kind, key)
        if self.view == "desktop":
            if key == "ok":
                self.view = "menu"
        elif self.view == "menu":
            n = len(self.ITEMS)
            if key in ("up", "down"):
                self.cursor = (self.cursor + (1 if key == "down" else -1)) % n
                self.top = min(max(self.top, self.cursor - 3), self.cursor)
            elif key == "ok":
                self.view = "app"
            elif key == "back":
                self.view = "desktop"
        elif key == "back":
            self.view = "menu"
        self.render()

    def run(self):
        while True:
            self.render()
            time.sleep(1)

    def render(self):
        px = [[False] * W for _ in range(H)]

        def text(s, x, y, on=True):
            for ch in s.upper():
                glyph = FONT.get(ch, FONT[" "]).split()
                for gy, row in enumerate(glyph):
                    for gx, c in enumerate(row):
                        if c == "#" and 0 <= x + gx < W and 0 <= y + gy < H:
                            px[y + gy][x + gx] = on
                x += 6

        def fill(x0, y0, x1, y1, on=True):
            for y in range(max(y0, 0), min(y1, H)):
                for x in range(max(x0, 0), min(x1, W)):
                    px[y][x] = on

        text("DEMO", 1, 1)
        text("87%", 108, 1)
        fill(0, 9, W, 10)
        if self.view == "desktop":
            text(time.strftime("%H:%M:%S"), 40, 24)
            text("OK FOR MENU", 31, 44)
        elif self.view == "menu":
            for i, name in enumerate(self.ITEMS[self.top:self.top + 4]):
                y = 13 + i * 12
                sel = self.top + i == self.cursor
                if sel:
                    fill(0, y - 2, 122, y + 9)
                text(name, 4, y, on=not sel)
            fill(125, 11, 126, H)
            ty = 11 + (H - 11 - 8) * self.cursor // (len(self.ITEMS) - 1)
            fill(124, ty, 127, ty + 8)
        else:
            text(self.ITEMS[self.cursor], 4, 16)
            text("LAST: " + self.last, 4, 30)
            text("BACK TO RETURN", 4, 50)
        rows = ["".join("x" if p else "." for p in row) for row in px]
        if rows != self.state.rows:
            self.state.update(rows=rows)


# --- HTTP ----------------------------------------------------------------------------

def make_handler(state, device, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            if not self.path.startswith("/stream"):
                line = fmt % args
                if token:
                    line = line.replace(token, "***")
                sys.stderr.write("%s %s\n" % (self.address_string(), line))

        def reply(self, code, obj):
            body = (json.dumps(obj, separators=(",", ":")) + "\n").encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlparse(self.path)
            q = {k: v[-1] for k, v in parse_qs(url.query).items()}
            if token and not secrets.compare_digest(q.get("token", ""), token):
                return self.reply(403, {"ok": False, "error": "wrong token"})
            if url.path == "/state":
                return self.reply(200, state.snapshot())
            if url.path == "/input":
                key, kind = q.get("key", ""), q.get("type", "short")
                if key not in KEYS or kind not in ("short", "long"):
                    return self.reply(400, {"ok": False, "error": "key: up/down/left/right/ok/back, type: short/long"})
                try:
                    device.press(key, kind)
                except (OSError, IOError) as e:
                    return self.reply(503, {"ok": False, "error": str(e)})
                return self.reply(200, {"ok": True})
            if url.path == "/stream":
                return self.stream(split=q.get("split") == "2")
            self.reply(404, {"ok": False, "error": "try /stream, /state or /input"})

        def stream(self, split):
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            seen = -1
            try:
                while True:
                    with state.cond:
                        state.cond.wait_for(lambda: state.seq != seen, timeout=5)
                    snap = state.snapshot()
                    seen = snap["seq"]
                    if split:
                        rows = snap["rows"] or [None, None]
                        half = len(rows) // 2
                        lines = [dict(snap, part=0, rows=rows[:half] if snap["rows"] else None),
                                 dict(snap, part=1, rows=rows[half:] if snap["rows"] else None)]
                    else:
                        lines = [snap]
                    self.wfile.write("".join(json.dumps(l, separators=(",", ":")) + "\n" for l in lines).encode())
                    self.wfile.flush()
                    time.sleep(0.08)  # at most ~12 frames a second; later changes coalesce
            except (BrokenPipeError, ConnectionResetError):
                pass

    return Handler


def load_token(args):
    if args.no_token:
        return None
    if args.token:
        return args.token
    path = os.path.expanduser("~/.config/flipper-bridge/token")
    try:
        with open(path) as f:
            tok = f.read().strip()
        if tok:
            return tok
    except OSError:
        pass
    tok = secrets.token_urlsafe(12)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        f.write(tok + "\n")
    return tok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port (default: find the Flipper)")
    ap.add_argument("--listen", default="127.0.0.1:8765", help="address:port to serve on (default 127.0.0.1:8765)")
    ap.add_argument("--token", help="token clients must send (default: generated, kept in ~/.config/flipper-bridge/token)")
    ap.add_argument("--no-token", action="store_true", help="accept requests without a token")
    ap.add_argument("--demo", action="store_true", help="serve a fake Flipper instead")
    args = ap.parse_args()

    state = State()
    device = Demo(state) if args.demo else Flipper(state, args.port)
    threading.Thread(target=device.run, daemon=True).start()

    host, _, port = args.listen.rpartition(":")
    token = load_token(args)
    server = ThreadingHTTPServer((host or "127.0.0.1", int(port)), make_handler(state, device, token))
    server.daemon_threads = True
    print("flipper-bridge on %s:%s%s" % (host or "127.0.0.1", port, "" if token else " (no token)"), flush=True)
    if token:
        print("token: %s" % token, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
```

</details>
