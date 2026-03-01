# Architecture

## Overview

Jeeves runs as two systemd services on a Raspberry Pi 5:

| Service | Process | Port |
|---------|---------|------|
| `pi-assistant.service` | HTTP daemon + brain + supervisor | 8001 |
| `pi-discord-bot.service` | asyncio Discord client | — |

---

## Request Lifecycle

### Normal Chat

```
User: "jeeves what's the weather like?"
  ↓
Discord bot (on_message)
  ↓ POST /ask { user, server_id, channel_name }
Pi daemon (http_server.py)
  ↓
BrainPipeline.process()
  ├── Tool layer check → no match
  ├── Load conversation history (SQLite)
  ├── Load persona + memory
  └── Call Ollama qwen2.5:1.5b
  ↓
Response → Discord channel
```

### Tool Command

```
User: "jeeves !email unread"
  ↓
Discord bot → POST /ask
  ↓
BrainPipeline.process()
  ↓
ToolRegistry.execute(user_text, context, server_id)
  ↓ prefix match "!email"
handle_email_tool(text)
  ↓
Response → Discord channel (instant)
```

### Task Command (streaming)

```
User: "jeeves !task build a pokemon game in pygame"
  ↓
Discord bot → POST /ask
  ↓
handle_task_tool(text, server_id="1034...")
  ↓
threading.Thread → run_coding_task()  ← returns immediately
  ↓ "Task started — streaming updates incoming..."
Discord bot receives response
  ↓ creates Thread on that message ("🤖 Task in progress")

[Background thread on Pi]:
  _notify("🤖 Task: ...")           → queued in memory
  _notify("📁 Project: ...")        → queued
  _notify("🔍 Type: pygame_game")   → queued
  _notify("📋 Planning with ...")   → queued
  [gemma3:4b planning — 3-8 min]
  _notify("⏳ Still planning (15s)") → every 15s heartbeat
  ...
  _notify("✅ Plan ready")
  _notify("📝 Writing SPEC.md...")
  POST /copilot/task → VS Code bridge
  _notify("✅ SPEC.md written on PC")
  _notify("🚀 VS Code opening...")
  _notify("🏁 Jeeves done. Copilot is building...")

[Discord bot notify poller — runs every 2s]:
  GET /notify?server_id=1034...
  ← {"messages": ["🤖 Task: ...", "📁 Project: ...", ...]}
  → thread.send() for each message
  → when "Jeeves done." detected → unregister thread
```

---

## Component Map

```
/mnt/storage/pi-assistant/
├── assistant/
│   ├── http_server.py       ← HTTP daemon, notify queue, ThreadedHTTPServer
│   ├── brain.py             ← AssistantBrain (assembles pipeline)
│   ├── brain_core.py        ← AssistantBase, ToolRegistry, keepalive
│   ├── brain_pipeline.py    ← process(), history, facts, LLM call
│   ├── brain_db.py          ← all SQLite access (thread-safe WAL mode)
│   ├── schema.sql           ← table definitions
│   ├── supervisor.py        ← background loop: job queue + Architect/Coder/QA
│   ├── indexer.py           ← project file indexer (AST + LLM summaries)
│   ├── task_router.py       ← multi-model routing (core/coder/reasoner)
│   └── audit_log.py         ← tool call log
│
├── tools/
│   ├── assistant_tools.py   ← tool dispatcher (!task, !index, !email, etc.)
│   ├── coding_agent.py      ← !task orchestration, SPEC.md builder
│   ├── discord/
│   │   ├── core.py          ← Discord client, notify poller, thread creation
│   │   ├── routing.py       ← activation word, channel filtering, rate limiting
│   │   ├── daemon_client.py ← async HTTP calls to /ask
│   │   └── ...
│   ├── vscode/
│   │   └── vscode_tools.py  ← VS Code bridge client
│   ├── calendar/            ← Google Calendar integration
│   ├── email/               ← IMAP/SMTP
│   ├── design/              ← UI/UX design system generator
│   ├── cast/                ← Chromecast control
│   └── sitekit/             ← business site kit generator
│
├── config/
│   ├── config.json          ← global model + system config
│   ├── servers/             ← per-server JSON configs
│   ├── personas/            ← persona text files
│   └── lore/                ← lore documents (for Scribe mode)
│
├── memory/                  ← per-server markdown memory files
├── data/
│   └── jeeves.db            ← SQLite database
└── discord_modular.py       ← Discord bot entry point
```

---

## Database Schema

### Core Tables

| Table | Purpose |
|-------|---------|
| `conversations` | Per-server chat history |
| `projects` | Project registry |
| `files` | Project file contents + snapshots |
| `tasks` | Task queue (from Discord `!task`) |
| `plans` | Architect-generated plans |
| `subtasks` | Individual implementation steps |
| `agent_runs` | Architect/Coder/QA execution log |
| `memory_notes` | Persistent memory per server |
| `tool_audit` | Every tool call logged |
| `backlog_items` | QA-generated issue backlog |

### Project Index Tables

| Table | Purpose |
|-------|---------|
| `project_files` | Indexed file paths, language, summary, mtime |
| `project_symbols` | Python classes and functions with line numbers |
| `project_imports` | Import relationships between files |

### Job Queue Tables

| Table | Purpose |
|-------|---------|
| `jobs` | Background job queue (index_project, etc.) |
| `job_runs` | Job execution history |

---

## Supervisor Loop

The supervisor runs as a daemon thread inside `pi-assistant.service`. Every 5 seconds:

1. Check for pending **jobs** (indexing, maintenance) — process one
2. If no jobs, check for pending **coding tasks** — run Architect → Coder → QA pipeline

This means indexing runs in the background without blocking chat or task responses.

---

## Notify Queue (Streaming)

The notify system is how long-running tasks stream progress to Discord without blocking:

```
coding_agent.py
  → requests.post("http://127.0.0.1:8001/notify", {server_id, content})
  → http_server.py appends to in-memory queue[server_id]

Discord bot (asyncio, every 2s)
  → aiohttp.get("http://127.0.0.1:8001/notify?server_id=...")
  → http_server.py pops and returns queue
  → bot sends each message to the active task thread
```

Key properties:
- `ThreadedHTTPServer` — `/notify` POST never blocks `/ask` processing
- Session recreation on failure — poller survives connection drops
- Thread auto-unregisters when `"Jeeves done."` is detected

---

## Multi-Model Routing

`task_router.py` routes prompts to the right model:

| Route | Model | Used For |
|-------|-------|---------|
| `core` | `qwen2.5:1.5b` | General chat, always warm |
| `reasoner` | `gemma3:4b` | Task planning, structured output |
| `coder` | `qwen2.5-coder:7b` | Code generation |
| `summarizer` | `gemma2:2b` | File summaries, QA |

---

## Project Indexer

`!index [path]` queues a background job. The supervisor runs it between tasks:

1. Walk directory, skip `__pycache__`, `.git`, `venv`, `node_modules`
2. Detect language from extension
3. Extract Python symbols (classes, functions, imports) via AST — no LLM needed
4. Optionally summarize each file with `qwen2.5:1.5b`
5. Store in `project_files`, `project_symbols`, `project_imports`
6. Incremental — skips files where `mtime` hasn't changed

`!findfile` and `!findsymbol` query SQLite directly — instant results.
