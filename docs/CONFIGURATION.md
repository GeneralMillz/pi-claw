# Configuration Guide

## Global Config (`config.json`)

Located at `/mnt/storage/pi-assistant/config.json`

```json
{
  "model": "qwen2.5:1.5b",
  "system": "You are Jeeves, a personal AI assistant running on a Raspberry Pi 5...",
  "max_history": 6,
  "context_tokens": 4096,
  "keepalive_enabled": true,
  "keepalive_interval": 600,
  "model_prefs": {
    "qwen2.5:1.5b": {
      "max_history": 6,
      "context_tokens": 4096,
      "facts_enabled": false,
      "identity_override": true,
      "short_reply_mode": true
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `model` | Default chat model (always-warm model) |
| `max_history` | Number of past messages to include in context |
| `context_tokens` | Token budget for conversation history |
| `keepalive_interval` | Seconds between keepalive pings to Ollama (prevents model unload) |
| `identity_override` | Use persona file instead of model's default identity |
| `short_reply_mode` | Append "be brief" instructions to system prompt |

---

## Server Config (`config/servers/<server_id>.json`)

One file per Discord server. Filename is the Discord guild ID.

```json
{
  "name": "my_server",
  "mode": "founder",
  "allowed_channels": ["jeeves"],
  "activation_word": "jeeves",
  "tools_enabled": true,
  "persona_file": "config/personas/jeeves_founder.txt",
  "channel_overrides": {
    "dev": { "tools_enabled": true, "tone": "analytical" },
    "ops": { "tools_enabled": true, "tone": "operational" }
  }
}
```

| Field | Description |
|-------|-------------|
| `name` | Human-readable server name |
| `mode` | `founder`, `family`, `lore` — affects persona defaults |
| `allowed_channels` | Bot only responds in these channels |
| `activation_word` | Trigger word (e.g. "jeeves", "atlas") |
| `tools_enabled` | Whether `!task`, `!email`, etc. are available |
| `persona_file` | Path to persona text file |
| `channel_overrides` | Per-channel config overrides |

---

## Personas (`config/personas/`)

Plain text files. Injected as the system prompt.

**jeeves_founder.txt** — Default persona. Technical, precise, brief.

```
You are Jeeves, Jerry's personal AI assistant running locally on a Raspberry Pi 5.
You think like a systems architect and communicate like a senior engineer.
You never guess. You verify, confirm, and execute with discipline.

## Code Navigation Protocol
Before writing or editing any code:
1. Use !findfile or !findsymbol to locate the exact file.
2. Use !vscode read <path> to understand the existing implementation.
3. Patch minimally. Never rewrite a file to fix one line.
```

**jeeves_family.txt** — Casual, warm tone for family server.

**scribe_lore.txt** — Lore archivist persona. Stays in-world, only references the lore document.

### Creating a Custom Persona

```bash
nano config/personas/atlas.txt
```

```
You are Atlas, a no-nonsense engineering AI...
```

Reference it in the server config:
```json
{
  "activation_word": "atlas",
  "persona_file": "config/personas/atlas.txt"
}
```

---

## Memory (`memory/`)

Per-server markdown files. Injected into every prompt for that server.

```
memory/
  personal.md          ← injected for server 1034... (founder server)
  family.md            ← injected for family server
```

Format is freeform markdown. Jeeves reads it as context:

```markdown
# About Jerry

- Software developer, Raspberry Pi enthusiast
- Main projects: Jeeves, pi-media-server, game dev hobby projects
- Preferred stack: Python, FastAPI, React
- PC: Windows 11, VS Code, GitHub Copilot
```

---

## Multi-Model Routing (`task_router.py`)

Controls which Ollama model handles each type of request:

```python
MODELS = {
    "core":       "qwen2.5:1.5b",    # always warm — general chat
    "reasoner":   "gemma3:4b",        # task planning, structured output
    "coder":      "qwen2.5-coder:7b", # code generation
    "summarizer": "gemma2:2b",        # file summaries, QA
}
```

To swap a model, edit this dict. No restart required (`.pyc` cache clears automatically on next invocation if you delete it).

---

## Task Planning Models

The `!task` command uses the `reasoner` model. To change it:

```bash
python3 << 'EOF'
path = "/mnt/storage/pi-assistant/assistant/task_router.py"
with open(path) as f: content = f.read()
content = content.replace('"reasoner":   "gemma3:4b"', '"reasoner":   "mistral:7b"')
with open(path, "w") as f: f.write(content)
print("done")
EOF
```

Recommended models for reasoning on Pi 5:

| Model | Size | Speed | Quality |
|-------|------|-------|---------|
| `gemma3:4b` | 3.3GB | ~3-5 min | ⭐⭐⭐⭐ |
| `qwen2.5:7b` | 4.7GB | ~7-8 min | ⭐⭐⭐⭐ |
| `mistral:7b` | 4.4GB | ~5-6 min | ⭐⭐⭐⭐ |
| `deepseek-r1:8b` | 5.2GB | slow + verbose | ⭐⭐⭐ |

---

## Project Indexer

The indexer runs as a background job. Configure what gets indexed by adjusting `SKIP_DIRS` in `indexer.py`:

```python
SKIP_DIRS = {
    "__pycache__", ".git", "node_modules", "venv", ".venv",
    "dist", "build", ".mypy_cache", ".pytest_cache",
}
```

Max file size (default 50KB — skips binaries):
```python
MAX_FILE_BYTES = 50_000
```

Run without LLM summaries (fast):
```
jeeves !index --no-summarize
```

Force re-index all files (ignore mtime):
```
jeeves !index --force
```

---

## Environment Variables (`.env`)

```env
DISCORD_TOKEN=your_bot_token

# Google Calendar (optional)
GOOGLE_CREDENTIALS_PATH=/mnt/storage/pi-assistant/google_credentials.json

# Email (optional)
IMAP_HOST=imap.gmail.com
IMAP_PORT=993
IMAP_USER=you@gmail.com
IMAP_PASS=your_app_password
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
```

---

## VS Code Bridge

Update the bridge host in `coding_agent.py` to match your PC's local IP:

```python
VSCODE_HOST = "http://192.168.1.153:5055"
```

Find your PC's IP:
```powershell
ipconfig | findstr "IPv4"
```
