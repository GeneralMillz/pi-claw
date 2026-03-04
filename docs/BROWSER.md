# 🌐 BROWSER.md — Pinchtab Browser Tool

Jeeves controls a real headless Chromium browser via **Pinchtab** — a lightweight Go binary that wraps Chromium over HTTP. No Playwright. No Selenium. No Python browser drivers.

---

## Architecture

```
Discord  !browse <url>
       │
       ▼
tools/browser/browser_tools.py
       │  HTTP  127.0.0.1:9867
       ▼
Pinchtab  (Go binary, systemd service)
       │
       ▼
Chromium  (headless)
```

Pinchtab runs as a systemd service on the Pi and binds to localhost only — it is never reachable from your LAN.

---

## Installation

### 1. Install Chromium

```bash
sudo apt install -y chromium-browser
```

### 2. Install Pinchtab

```bash
curl -fsSL https://pinchtab.com/install.sh | bash
pinchtab --version   # verify
```

### 3. Create the systemd service

```bash
sudo nano /etc/systemd/system/pinchtab.service
```

Paste:

```ini
[Unit]
Description=Pinchtab headless browser bridge
After=network.target

[Service]
ExecStart=/usr/local/bin/pinchtab
Restart=always
RestartSec=5
Environment=BRIDGE_BIND=127.0.0.1
Environment=BRIDGE_PORT=9867
Environment=BRIDGE_HEADLESS=true
Environment=BRIDGE_BLOCK_ADS=true
Environment=BRIDGE_STEALTH=light

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable pinchtab
sudo systemctl start pinchtab
```

### 4. Deploy the browser tool

```bash
mkdir -p /mnt/storage/pi-assistant/tools/browser
cp tools/browser/browser_tools.py /mnt/storage/pi-assistant/tools/browser/
touch /mnt/storage/pi-assistant/tools/browser/__init__.py
```

### 5. Wire into assistant_tools.py

The safe import block in `tools/assistant_tools.py` — if already present, skip this:

```python
try:
    from tools.browser.browser_tools import handle_browse_tool, is_browse_query
except ImportError:
    def handle_browse_tool(text): return False, ""
    def is_browse_query(text): return False
```

Add to your dispatch loop (before the brain pipeline fallback):

```python
if lo.startswith("!browse") or is_browse_query(lo):
    handled, response = handle_browse_tool(stripped)
    if handled:
        return response
```

### 6. Restart Jeeves

```bash
sudo systemctl restart pi-assistant.service
```

---

## Commands

| Command | Description |
|---------|-------------|
| `!browse <url>` | Navigate to URL and return page text |
| `!browse text` | Read text of the current page |
| `!browse snap [url]` | List interactive elements with click refs |
| `!browse click <ref>` | Click element by ref (e0, e1, e2…) — auto-reads page after |
| `!browse fill <ref> <text>` | Fill an input field |
| `!browse press <key>` | Press a key (Enter, Tab, Escape, Alt+Left…) |
| `!browse scroll [ref]` | Scroll page down or scroll to element |
| `!browse back` | Navigate back (Alt+Left) |
| `!browse screenshot` | Capture viewport — returned as Discord attachment |
| `!browse tabs` | List all open tabs |
| `!browse eval <js>` | Run JavaScript and return result |
| `!browse health` | Check Pinchtab is reachable |

---

## Typical Workflows

### Read a page

```
!browse https://news.ycombinator.com
```

Jeeves navigates, waits 1 second for the page to settle, then returns readable text.

### Find and click a link

```
!browse snap https://example.com
!browse click e3
```

`snap` shows all interactive elements and their refs. `click` follows the ref and auto-reads the new page.

### Fill a search form and submit

```
!browse https://google.com
!browse snap
!browse fill e3 raspberry pi 5 benchmarks
!browse press Enter
!browse text
```

### Screenshot

```
!browse screenshot
```

Returns as a Discord file attachment (JPEG, 80% quality).

### Run JavaScript

```
!browse eval document.title
!browse eval window.location.href
```

---

## Natural Language Triggers

The browser tool also responds to natural language that implies navigation:

- `go to news.ycombinator.com`
- `browse to github.com/microsoft/markitdown`
- `navigate to reddit.com`
- `visit stackoverflow.com`

These are detected by `is_browse_query()` and routed automatically — no `!browse` prefix needed.

---

## Token Efficiency

Pinchtab's `/text` endpoint strips all HTML and returns only readable content — much cheaper than vision/screenshot approaches.

| Method | Approx tokens |
|--------|--------------|
| `/text` (default) | ~800 |
| Interactive snapshot | ~3,600 |
| Full snapshot | ~10,500 |
| Screenshot (vision model) | ~2,000 |

For scraping or research tasks, `/text` is the most efficient. Use `snap` only when you need to interact with specific elements.

---

## Pinchtab API Reference

`browser_tools.py` maps Jeeves commands to these Pinchtab endpoints:

| Endpoint | Method | Body / Params | Purpose |
|----------|--------|---------------|---------|
| `/health` | GET | — | Liveness check |
| `/navigate` | POST | `{url}` | Go to URL |
| `/text` | GET | — | Extract readable page text |
| `/snapshot` | GET | `?format=text&filter=interactive` | Accessibility tree with refs |
| `/action` | POST | `{kind:"click", ref:"e3"}` | Click element |
| `/action` | POST | `{kind:"fill", ref:"e3", value:"..."}` | Fill input |
| `/action` | POST | `{kind:"press", key:"Enter"}` | Press key |
| `/action` | POST | `{kind:"scroll"}` | Scroll down |
| `/screenshot` | GET | `?quality=80` | JPEG as base64 |
| `/tabs` | GET | — | List open tabs |
| `/evaluate` | POST | `{expression:"..."}` | Run JavaScript |

---

## Troubleshooting

**Pinchtab not running:**
```bash
sudo systemctl status pinchtab
sudo systemctl start pinchtab
# See startup errors:
journalctl -u pinchtab -n 30
```

**`!browse health` says offline:**
```bash
curl http://127.0.0.1:9867/health
```

**Page returns no text:**
- JS-heavy pages may need more time — `!browse eval document.readyState` should return `complete`
- `!browse screenshot` to visually inspect what Chromium sees
- Try `!browse snap` to check if elements are detected at all

**Site blocking headless browsers:**
- Change `BRIDGE_STEALTH=light` to `BRIDGE_STEALTH=medium` or `BRIDGE_STEALTH=full` in the service env
- Restart: `sudo systemctl restart pinchtab`

**Back navigation not working:**
- `!browse back` uses `Alt+Left` via the `/action` press endpoint
- Verify with `!browse eval window.history.length` — should be > 1 if there's history to go back to
