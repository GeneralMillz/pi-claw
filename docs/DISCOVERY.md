# 🔍 Discovery Layer

**Auto-index GitHub repos dropped into `/skills/` and `/tools/` directories.**

The Discovery Layer automatically scans for new repositories, classifies them by type (skill, tool, mixed), and displays them in the dashboard with search, filtering, and statistics. It runs on a 5-minute schedule via systemd and never interferes with skill injection or tool registry.

---

## Overview

When you clone a GitHub repository into `/mnt/storage/pi-assistant/skills/` or `/tools/`, the Discovery scanner automatically detects it, analyzes its contents, and makes it visible in the Jeeves dashboard. No manual registration needed.

```
Drop repo → Scanner runs → Index updated → Dashboard shows it
   (5m)        (auto)      (JSON file)     (DiscoveryView.js)
```

---

## How It Works

### Scanner (`discovery/discover.py`)

Runs on a 5-minute schedule via systemd timer. Also callable via the HTTP endpoint `/api/discover/refresh` for manual triggering.

**Algorithm:**

1. **Walk `/skills/` and `/tools/`** — iterate top-level subdirectories only
2. **For each repo directory:**
   - Check for `SKILL.md` at depth 1 → classify as "skill"
   - Else check for `README.md` → classify as "skill"
   - Else count `.md` files → classify based on count
   - Else check for `.py` files → classify as "tool"
   - Else check for both `.md` + `.py` → classify as "mixed"
   - Else skip (ignore)
3. **Collect metadata:**
   - List all `.md` files at depth 1
   - List all `.py` files at depth 1
   - Compute total size recursively (all descendants)
   - Get latest modification time recursively
4. **Write atomically:**
   - Write to `discovery/index.json.tmp`
   - Rename to `discovery/index.json` (atomic on POSIX)
   - Caller sees consistent data (never partial/corrupted)

**Error handling:**
- If scan fails, logs error to stdout — doesn't crash
- If `/skills/` or `/tools/` doesn't exist, returns empty index (graceful)
- On HTTP API error, returns `{"ok": false, "error": str(e)}`

### API Module (`discovery/api.py`)

Pure Python API with no side effects. Read-only access to `index.json`.

**Key functions:**

```python
read_index() -> list[dict]
    # Reads index.json. Returns empty list if missing.

search(query: str) -> list[dict]
    # Filters by name, path, or md_files containing query (case-insensitive).

filter_by_type(type_str: str) -> list[dict]
    # Returns entries where type == type_str. "all" returns all.

filter_by_source(source_str: str) -> list[dict]
    # Returns entries where source == source_str. "all" returns all.

get_summary() -> dict
    # Returns {total, by_type, by_source, last_scanned}.
```

### HTTP API

Three endpoints on the main HTTP daemon:

#### `GET /api/discovery`

**Query parameters:**
```
type_filter=all|skill|tool|mixed    (default: all)
source_filter=all|skills|tools      (default: all)
```

**Response:**
```json
{
  "ok": true,
  "index": [
    {
      "name": "awesome-systematic-trading",
      "type": "skill",
      "source": "skills",
      "path": "/mnt/storage/pi-assistant/skills/awesome-systematic-trading",
      "md_files": ["/mnt/storage/.../README.md", "/mnt/storage/.../INSTALL.md"],
      "py_files": [],
      "size": 245120,
      "modified": "2026-03-23T11:00:00Z"
    }
  ]
}
```

#### `POST /api/discover/refresh`

Triggers the scanner immediately. Waits for completion, then returns.

**Response:**
```json
{
  "ok": true,
  "message": "Discovery scan completed in 2.3s"
}
```

#### `GET /api/discovery/summary`

Returns aggregate statistics.

**Response:**
```json
{
  "ok": true,
  "total": 33,
  "by_type": {
    "skill": 22,
    "tool": 8,
    "mixed": 3
  },
  "by_source": {
    "skills": 25,
    "tools": 8
  },
  "last_scanned": "2026-03-23T14:32:18Z"
}
```

---

## Classification Rules (Option C Hybrid)

For each top-level directory under `/skills/` or `/tools/`, the scanner applies this decision tree:

```
Has SKILL.md anywhere at depth 1?
    YES → type = "skill"

    NO → Has README.md?
        YES → type = "skill"

        NO → Count .md files
            ≥2 .md files  → type = "skill"
            1 .md file   → type = "skill"
            0 .md files  → Check .py files

                         Has .py files?
                            YES → Has both .md + .py?
                                    YES → type = "mixed"
                                    NO  → type = "tool"
                            NO  → skip (ignore)
```

**Practical examples:**

| Repo | Files | Type | Reason |
|------|-------|------|--------|
| awesome-systematic-trading | README.md (only) | skill | README.md is present |
| mcp-server | README.md + 12 .py files | mixed | Both .md and .py |
| OpenAlice | README.md + Python source | mixed | Both .md and .py |
| ok-skills | SKILL.md + 20 SKILL.md (subdirs) | skill | Has SKILL.md at depth 1 |
| paperclip | README.md + setup.py + pyproject.toml | mixed | Both .md and .py |
| get-shit-done | 8 .py files (no .md) | tool | Python only, no markdown |
| archive (old code) | Only .json + .txt | — | Skipped (no .md or .py) |

---

## index.json Schema

Machine-generated file at `/mnt/storage/pi-assistant/discovery/index.json`.

**Example:**
```json
[
  {
    "name": "awesome-systematic-trading",
    "type": "skill",
    "source": "skills",
    "path": "/mnt/storage/pi-assistant/skills/awesome-systematic-trading",
    "md_files": [
      "/mnt/storage/pi-assistant/skills/awesome-systematic-trading/README.md",
      "/mnt/storage/pi-assistant/skills/awesome-systematic-trading/INSTALL.md"
    ],
    "py_files": [],
    "size": 245120,
    "modified": "2026-03-23T11:00:00Z"
  },
  {
    "name": "mcp-server",
    "type": "mixed",
    "source": "skills",
    "path": "/mnt/storage/pi-assistant/skills/mcp-server",
    "md_files": [
      "/mnt/storage/pi-assistant/skills/mcp-server/README.md",
      "/mnt/storage/pi-assistant/skills/mcp-server/SETUP.md"
    ],
    "py_files": [
      "/mnt/storage/pi-assistant/skills/mcp-server/server.py",
      "/mnt/storage/pi-assistant/skills/mcp-server/tools.py"
    ],
    "size": 512340,
    "modified": "2026-03-22T09:15:30Z"
  }
]
```

**Field definitions:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Top-level directory name (basename of path) |
| `type` | "skill" \| "tool" \| "mixed" | Classification result |
| `source` | "skills" \| "tools" | Which root directory (for visual distinction) |
| `path` | string | Absolute filesystem path to the repo |
| `md_files` | string[] | Absolute paths to `.md` files found at depth 1 |
| `py_files` | string[] | Absolute paths to `.py` files found at depth 1 |
| `size` | int | Total bytes (all descendants, recursive) |
| `modified` | string | ISO 8601 timestamp of newest file in tree |

---

## Systemd Automation

Two units enable automatic 5-minute scanning:

### Timer (`/etc/systemd/system/jeeves-discover.timer`)

```ini
[Unit]
Description=Jeeves Discovery Scanner Timer
After=network-online.target
Wants=network-online.target

[Timer]
# Run 60 seconds after boot, then every 5 minutes
OnBootSec=60s
OnUnitActiveSec=5min
# Maintain wall-clock schedule even if timer is stopped/restarted
Persistent=true

[Install]
WantedBy=timers.target
```

### Service (`/etc/systemd/system/jeeves-discover.service`)

```ini
[Unit]
Description=Jeeves Discovery Scanner
After=network-online.target

[Service]
Type=oneshot
ExecStart=/mnt/storage/pi-assistant/venv/bin/python3 /mnt/storage/pi-assistant/discovery/discover.py
WorkingDirectory=/mnt/storage/pi-assistant
User=pi
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Managing the Timer

```bash
# Enable timer (runs on boot and every 5 min)
sudo systemctl enable --now jeeves-discover.timer

# Check status
sudo systemctl status jeeves-discover.timer
sudo systemctl list-timers jeeves-discover.timer

# View scan logs
journalctl -u jeeves-discover.service -f

# Manually trigger a scan
sudo systemctl start jeeves-discover.service

# Disable timer (stops 5-min schedule)
sudo systemctl disable --now jeeves-discover.timer
```

---

## Dashboard Panel (DiscoveryView.js)

React component that renders an interactive table with filtering and search.

### Features

1. **Summary Stats Grid**
   - Total repos count
   - Breakdown by type (skill, tool, mixed)
   - Matches `.node-grid` pattern from existing Jeeves UI

2. **Filter Controls**
   - Type buttons: All, Skill, Tool, Mixed
   - Source buttons: All, Skills, Tools
   - Search input: matches by name, path, or .md filename
   - Refresh button: triggers `/api/discover/refresh`

3. **Table**
   - Columns: Name | Type | Source | MD | PY | Size | Modified
   - Type badges: skill (green), tool (blue), mixed (amber)
   - Searchable and filterable
   - Hover states for accessibility
   - Right-aligned numeric columns (proper alignment)

4. **Footer**
   - "Showing X of Y repos"
   - Last scanned timestamp

### Styling

All CSS uses Jeeves design variables:

| Token | Value | Used for |
|-------|-------|----------|
| `--ui` | Syne Mono | Labels (0.1em letter-spacing, uppercase) |
| `--mono` | IBM Plex Mono | Table data |
| `--amber` | #c8933a | Filter buttons, type badges (mixed) |
| `--green2` | #5aaa6a | Type badges (skill) |
| `--blue2` | #5a80b8 | Type badges (tool) |
| `--bg` | #0b0c0e | Background |
| `--bg2` | #111318 | Input backgrounds |
| `--bg3` | #181b22 | Table row hover state |
| `--border` | — | Borders |
| `--text` | — | Primary text |
| `--text2` | — | Secondary text |
| `--text3` | — | Tertiary text (muted) |

### Responsive Design

- Summary stats: CSS Grid with `auto-fill, minmax(140px, 1fr)` for responsive card layout
- Filters: Flex with `flex-wrap` — buttons stack on mobile
- Table: Horizontal scroll via `.mc-table-wrap` class
- Sticky headers: remain visible during vertical scroll

---

## Rollback Strategy

The Discovery Layer is **completely optional and non-invasive**. If you need to remove it:

```bash
# Option 1: Disable the timer (stops auto-scanning)
sudo systemctl disable --now jeeves-discover.timer

# Option 2: Delete discovery directory (safe — machine-generated files)
rm -rf /mnt/storage/pi-assistant/discovery/

# Option 3: Remove UI (revert git changes)
git checkout pi-claw-main/docs/  # reverts doc appends
git checkout jeeves-ui/          # reverts DiscoveryView.js + API routes

# Option 4: Remove systemd units
sudo rm /etc/systemd/system/jeeves-discover.*
sudo systemctl daemon-reload
```

**After removal:** skill injection, tool registry, and brain pipeline continue functioning identically. Zero regressions.

---

## Verification Steps

### 1. Test Scanner Manually

```bash
cd /mnt/storage/pi-assistant
python3 discovery/discover.py
cat discovery/index.json | python3 -m json.tool | head -60
```

Expected: JSON array with 20+ repos, properly classified.

### 2. Verify Classification

```bash
python3 -c "
import json
idx = json.load(open('discovery/index.json'))
print('Total:', len(idx))
for e in idx:
    print(f'{e[\"type\"].ljust(8)} {e[\"source\"].ljust(8)} {e[\"name\"]}')
"
```

Expected: Mix of skill/tool/mixed types, proper source labels.

### 3. Test HTTP Endpoints

```bash
# All repos
curl http://localhost:8100/api/discovery | python3 -m json.tool | head -30

# Only skills
curl "http://localhost:8100/api/discovery?type_filter=skill" | python3 -m json.tool

# Summary stats
curl http://localhost:8100/api/discovery/summary | python3 -m json.tool
```

Expected: 200 responses with valid JSON.

### 4. Test Manual Refresh

```bash
curl -X POST http://localhost:8100/api/discover/refresh | python3 -m json.tool
```

Expected: `{"ok": true, "message": "..."}`.

### 5. Open Dashboard

- Navigate to `http://localhost:8100` (or your Jeeves IP)
- Click Discovery panel in sidebar
- Confirm table renders with all repos
- Test search, type filter, source filter
- Click Refresh button
- Check type badges (colors match rules)

### 6. Regression Checks

```bash
# Daemon health
curl http://localhost:8001/health | python3 -m json.tool

# Skill injection still works
curl -X POST http://localhost:8001/ask -d '{"server_id":"test","content":"!skill search"}'

# Coding pipeline still works (sends a task)
curl -X POST http://localhost:8001/ask -d '{"server_id":"test","content":"!task build a hello world"}'
```

Expected: All endpoints respond normally. Skill injection and coding tasks unaffected.

### 7. Drop a New Repo and Re-scan

```bash
git clone https://github.com/some-user/some-project /mnt/storage/pi-assistant/skills/test-repo
python3 discovery/discover.py
curl http://localhost:8100/api/discovery | python3 -m json.tool | grep -A5 test-repo
```

Expected: New repo appears in index with correct type and metadata.

---

## Files

```
/mnt/storage/pi-assistant/
  discovery/
    discover.py        ← Scanner executable
    api.py             ← Pure module
    index.json         ← Output (gitignored, machine-generated)

  jeeves-ui/
    server.py          ← +3 FastAPI endpoints
    static/
      components/views/
        DiscoveryView.js  ← React panel
      js/
        constants.js     ← +1 NAV_VIEWS entry
        app.js           ← +1 router branch
      index.html         ← +1 script tag

/etc/systemd/system/
  jeeves-discover.service
  jeeves-discover.timer
```

---

## Performance

- **Scanner runtime:** 2–5 seconds (depends on repo count and total size)
- **Index size:** ~50 KB (33 repos)
- **API latency:** <100 ms (pure in-memory lookup)
- **Memory overhead:** <10 MB (single index load)
- **Disk I/O:** Atomic write only (no streaming, no partial reads)

No caching needed. Simple, fast, reliable.

---

## Frequently Asked Questions

**Q: Does Discovery affect skill injection?**
A: No. Skill injector still scans for `SKILL.md` inside repo subdirectories. Discovery indexes top-level repos only. Completely independent.

**Q: What if `/skills/` or `/tools/` doesn't exist?**
A: Scanner gracefully returns empty index. No crash.

**Q: Can I disable the timer without losing the UI?**
A: Yes. UI keeps working; just won't auto-refresh. Call `/api/discover/refresh` manually or via cron.

**Q: What if I delete `index.json`?**
A: Safe. Next scan regenerates it. Dashboard shows "loading" briefly.

**Q: Can Discovery index subdirectories inside repos?**
A: No. It only scans top-level dirs under `/skills/` and `/tools/`. Files at depth 1 are analyzed; subdirectories are recursively sized only.

**Q: How is "mixed" classified?**
A: A repo is "mixed" if it has both `.md` files at depth 1 AND `.py` files at depth 1. (Special upgrade from the base rules.)

**Q: Does Discovery run when the systemd timer is disabled?**
A: No, unless manually triggered via `/api/discover/refresh` or a cron job.

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) — Discovery subsystem in system context
- [SKILLS.md](SKILLS.md) — Skill injection (separate system)
- [TOOL_REGISTRY.md](TOOL_REGISTRY.md) — Tool registry (separate system)
