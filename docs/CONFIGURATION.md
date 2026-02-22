# Jeeves — Configuration Guide

---

## Server Config

Each Discord server gets its own JSON file at `config/servers/<server_id>.json`.

Get your server ID: Discord → Settings → Advanced → enable **Developer Mode** → right-click server → **Copy Server ID**

```json
{
  "name": "my_server",
  "mode": "founder",
  "allowed_channels": ["jeeves"],
  "activation_word": "jeeves",
  "tools_enabled": true,
  "persona_file": "default.txt",
  "short_reply_mode": true,
  "channel_overrides": {
    "dev": { "tools_enabled": true, "tone": "analytical" }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Human-readable label (used in logs only) |
| `mode` | string | Persona mode — matches a persona file |
| `allowed_channels` | array | Only respond in these Discord channels |
| `activation_word` | string | Word that triggers the assistant |
| `tools_enabled` | bool | Allow `!` tool commands in this server |
| `persona_file` | string | Text file in `config/personas/` |
| `short_reply_mode` | bool | `true` = 128 token replies, `false` = 250 token narrative |
| `facts_enabled` | bool | Enable keyword-scored fact injection (optional) |
| `fact_path` | string | Path to JSONL fact files (optional — omit if unused) |
| `channel_overrides` | object | Per-channel config overrides |

---

## Renaming the Assistant

Change `activation_word` to anything you like:

```json
{
  "activation_word": "friday",
  "persona_file": "friday.txt"
}
```

Create `config/personas/friday.txt`:
```
You are Friday, a sharp and efficient AI assistant.
...
```

Done — the bot now responds to "friday" instead of "jeeves".

---

## Per-Server Memory

Each server can have a persistent markdown file injected into every system prompt.

**Setup:**

1. Create `memory/YOUR_SERVER_ID.md` (copy from `memory/personal.example.md`)
2. Register it in `assistant/memory_loader.py`:

```python
_MEMORY_MAP = {
    "123456789012345678": "123456789012345678",  # maps server_id → filename (without .md)
}
```

**Format:**
```markdown
# Lines starting with # are stripped before injection

## About Me
- Name: Alex
- Role: Freelance developer

## Current Projects
- Project Falcon — React dashboard for client XYZ

## Preferences
- Keep responses brief
- I prefer bullet points
```

Edit anytime — no restart needed. The file is read fresh on every request.

---

## Persona Files

Located at `config/personas/<filename>.txt`. Referenced in server config.

**Default persona (`config/personas/default.txt`):**
```
You are Jeeves, a highly capable personal AI assistant.
You are direct, efficient, and technically sharp.
You keep responses concise and actionable.
```

Create as many as you need — one per server or mode.

---

## Model Configuration

`config/model_prefs.json`:

```json
{
  "model": "qwen2.5:1.5b",
  "context_tokens": 4096,
  "max_history": 6,
  "short_reply_mode": true,
  "facts_enabled": false
}
```

Server config `short_reply_mode` always overrides this file.

**Model-aware history caps (automatic):**
- `qwen2.5:0.5b` → max 2 history messages
- `qwen2.5:1.5b` → max 6 history messages
- Larger models → max 8 history messages

---

## VS Code Bridge

Update your PC's LAN IP in two places:

`tools/vscode/vscode_tools.py`:
```python
_DEFAULT_HOST = "http://192.168.1.x:5055"
```

`tools/coding_agent.py`:
```python
VSCODE_HOST = "http://192.168.1.x:5055"
```

Find your PC's IP: `ipconfig` (Windows) or `ip addr` (Linux)

---

## Chromecast (Optional)

`tools/cast/chromecast_tools.py`:
```python
DEVICES = {
    "tv":      "Your TV Device Name",
    "speaker": "Your Speaker Name",
}
```

Find device names:
```bash
source venv/bin/activate
python3 -c "import pychromecast; cc, _ = pychromecast.get_chromecasts(); [print(c.name) for c in cc]"
```

> **Note:** Chromecast Ultra (Cast OS) supports volume/mute only. Full playback control requires a Chromecast with Google TV device.

---

## Email (Optional)

`.env`:
```env
EMAIL_ADDRESS=you@gmail.com
EMAIL_PASSWORD=your_app_password   # Gmail: use App Password, not your real password
IMAP_SERVER=imap.gmail.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
```

For Gmail App Passwords: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)

---

## Fact Files (Optional)

For large knowledge bases where keyword scoring adds value. For most users, the memory markdown file is simpler and sufficient.

```
config/facts/YOUR_SERVER_ID/
  facts.jsonl
  projects.jsonl
```

Each line is a plain string or JSON:
```json
"The deadline for Project Falcon is March 15"
{"fact": "Client XYZ uses Stripe for payments", "tags": ["client", "payments"]}
```

Enable in server config:
```json
{
  "facts_enabled": true,
  "fact_path": "/path/to/config/facts/YOUR_SERVER_ID"
}
```
