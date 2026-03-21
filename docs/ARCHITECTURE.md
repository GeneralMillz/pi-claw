# 🏗️ ARCHITECTURE.md

## Overview

Jeeves is a multi-tool AI assistant daemon running on a Raspberry Pi 5. All user interaction flows through Discord. All local AI inference runs via Ollama on the Pi or LM Studio on the PC. External tools (VS Code bridge, Pinchtab, Gemini API) are reached over LAN or localhost.

---

## Full System Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         Discord Servers                            │
│               (multiple servers, multiple channels)                │
└───────────────────────────┬────────────────────────────────────────┘
                            │ message events
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│             pi-discord-bot.service  (asyncio)                     │
│             discord_bot.py — strips prefix, routes                │
│             POST /ask  ──────────────────────────────────────►    │
│             GET  /notify  (polls every 1s, streams to channel)    │
└───────────────────────────┬───────────────────────────────────────┘
                            │ HTTP :8001
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│             pi-assistant.service  (HTTP daemon)                   │
│             http_server.py — ThreadingHTTPServer                  │
│                                                                   │
│   /ask ──► brain_pipeline.py                                      │
│              │                                                    │
│              ├── tool_registry.py  (priority dispatch, NEW)       │
│              │     ├── priority 10: coding-agent                  │
│              │     │     triggers: !task, "build me", etc.        │
│              │     └── priority 20: tools-list                    │
│              │           triggers: !tools, !help tools            │
│              │                                                    │
│              ├── assistant_tools.py  (classic tool dispatch)      │
│              │     ├── !email / !calendar ──► IMAP / Google API   │
│              │     ├── !design ──────────► design_tools.py        │
│              │     ├── !cast ────────────► chromecast_tools.py    │
│              │     ├── !vscode ──────────► VS Code Bridge :5055   │
│              │     ├── !browse ──────────► browser_tools.py       │
│              │     │                          └► Pinchtab :9867   │
│              │     ├── !android ─────────► gemini_agent.py        │
│              │     └── !markdownify ─────► document_ingest.py     │
│              │                                                    │
│              └── brain_core.py  (LLM fallback)                    │
│                    └── Ollama qwen2.5:1.5b                        │
│                                                                   │
│   /notify ──► per-server streaming queue (deque)                  │
│   /status ──► skill selection waiting state (NEW)                 │
└───────────────────────────────────────────────────────────────────┘

Coding pipeline (tool_registry → coding-agent → VS Code Bridge):

  coding_agent.py (Pi)
    ├── skill_injector.py
    │     ├── score 978+ skills against project type
    │     ├── ≥5 candidates → Discord menu (interactive selection)
    │     └── inject top-N SKILL.md content into SPEC.md
    ├── task_router.py  → LM Studio 14B (PC) or Ollama (Pi fallback)
    └── POST /copilot/task → server.js (PC :5055)
          ├── write SPEC.md
          ├── write .continue/autoprompt.md
          ├── open VS Code (--new-window)
          └── write pending_prompt.txt → extension.js → Continue/Cursor
                └── Qwen 14B via LM Studio :1234

MCP Layer (mcp_registry.py + mcp_client.py):
  Tool catalogue → LM Studio 14B → tool calls → Pi executes → results → Discord

Streaming:
  Any tool → POST /notify → per-server deque
  Discord bot polls GET /notify every 1s → channel.send()
```

---

## Component Details

### pi-discord-bot.service
- `discord_bot.py` — asyncio, listens on all configured servers simultaneously
- Strips activation word, POSTs `{server_id, channel, user, content}` to `/ask`
- Polls `GET /notify?server_id=<id>` every 1 second — delivers streamed output to the right channel
- Handles Discord file attachments (reads bytes, sends as base64 in payload)
- Replies during skill selection (`/ask` with text `"1,3"`) are routed to `coding_agent.deliver_reply()`

### pi-assistant.service
- `http_server.py` v2.1.2 — stdlib `ThreadingHTTPServer` on port 8001
- Thread-per-request; SQLite is WAL mode for safe concurrent access
- `/ask` → checks `_try_deliver_reply()` first (consumes skill selection replies) → `brain_pipeline.py`
- `/notify` → drains a per-server deque (returns immediately with queued message or empty)
- `/status` → returns `skill_selection_waiting: [server_ids]` (new in v2.1.2)

### Tool Registry (`assistant/tool_registry.py`)
Introduced in session 6. Replaces the broken `self.tools.execute()` pattern that caused `!task` commands to silently fall through to the LLM.

```
registry.execute(text, brain, server_id)
  → iterate handlers in priority order (lowest number = highest priority)
  → first matching trigger wins
  → returns (handled: bool, response: str)
```

**Built-in registrations:**

| Priority | Name | Triggers |
|----------|------|----------|
| 10 | `coding-agent` | `!task`, `build me`, `create a`, `make a`, `write a`, `make me a`, `build a`, `code a`, `create me` |
| 20 | `tools-list` | `!tools`, `!help tools`, `list tools` |

**Extending:** Add `@registry.tool(triggers=[...])` blocks in `tool_registry.py`, or drop a `*_tool.py` file into `tools/` — `registry.load_all(tools_dir)` auto-discovers them. No changes to `brain_pipeline.py` ever needed.

### Tool Dispatcher (`tools/assistant_tools.py`)
Classic router for non-coding tools. Every import is wrapped in try/except — missing dependencies stub out silently. Each handler returns `(handled: bool, response: str)`.

| Handler | Trigger | Module |
|---------|---------|--------|
| `handle_email_tool` | `!email` | `tools/email/email_tools.py` |
| `handle_calendar_tool` | `!addevent`, `!getevents` | `tools/calendar/calendar_tools.py` |
| `handle_design_tool` | `!design` | `tools/design/design_tools.py` |
| `handle_cast_tool` | `!cast` | `tools/cast/chromecast_tools.py` |
| `handle_vscode_tool` | `!vscode` | `tools/vscode/vscode_tools.py` |
| `handle_browse_tool` | `!browse`, natural lang | `tools/browser/browser_tools.py` |
| `handle_android_command` | `!android` | `assistant/gemini_agent.py` |
| `handle_markitdown_command` | `!markdownify`, `!mdoc` | `assistant/markitdown_command.py` |

### Brain Pipeline (`assistant/brain_pipeline.py`)
Runs after tool registry and tool dispatcher both fail to claim the message:

1. Check `tool_registry.execute()` — handles `!task` and coding triggers
2. Check `assistant_tools.py` dispatch — handles all other `!` commands
3. If nothing matched: load conversation history from BrainDB (token-budgeted, newest-first)
4. Inject relevant memory notes (keyword overlap scoring)
5. POST to Ollama `qwen2.5:1.5b` via `/v1/chat/completions`
6. Save assistant reply to BrainDB

**Session 6 fix:** `self.tools` was never defined anywhere — every `!task` silently fell through to the LLM. Fixed by importing `registry` from `tool_registry.py`.

### Coding Agent (`tools/coding_agent.py`)
Orchestrates the full `!task` → SPEC.md → Continue pipeline.

Key subsystems:
- **Skill injection:** calls `find_skills_for_task()` with Discord notify/wait callbacks; interactive selection when ≥5 candidates found
- **Uncodixfy:** loads `/mnt/storage/pi-assistant/tools/uncodixfy.md` and appends UI rules to SPEC if present
- **Reply inbox:** `_reply_events` + `_reply_texts` dicts allow `http_server.py` to unblock a waiting skill-selection thread via `deliver_reply(server_id, text)`
- **Streaming:** every phase POSTs to `/notify` so Discord shows live progress

### Skill Injector (`tools/skill_injector.py`)
Scores all skills in the library against the project type and injects the top matches into SPEC.md.

**Skill roots scanned:**

| Path | Source |
|------|--------|
| `/mnt/storage/pi-assistant/skills/antigravity-awesome-skills/skills/` | 978 community skills |
| `/mnt/storage/pi-assistant/skills/claude-skills/` | alirezarezvani/claude-skills |
| `/mnt/storage/pi-assistant/skills/claude-scientific-skills/scientific-skills/` | K-Dense-AI |
| `/mnt/storage/pi-assistant/skills/superpowers/skills/` | 77.8k⭐ TDD methodology |
| `/mnt/storage/pi-assistant/skills/ui_ux_pro_max_skill/skills/` | 50+ UI styles, 97 palettes |
| `/mnt/storage/pi-assistant/skills/custom/` | your own skills |

**Interactive selection (≥5 candidates):**
1. Sends numbered Discord menu via `notify_fn`
2. Blocks for up to 60 seconds waiting on `wait_fn`
3. Reply `"1,3"` → select by number; `"all"` → all; Enter/`"auto"` → top-N auto-select
4. Timeout → auto-fallback to top-3

### BrainDB (`assistant/brain_db.py`)
SQLite with WAL mode. Single file at `/mnt/storage/pi-assistant/data/jeeves.db`.

| Table | Purpose |
|-------|---------|
| `conversations` | Per-server chat history (token-budgeted retrieval) |
| `projects` | Tracked coding projects |
| `tasks` + `subtasks` | Task queue and step execution |
| `agent_runs` | LLM call log (model, input, output, duration) |
| `memory_notes` | Persistent facts injected into future context |
| `tool_audit` | Every tool call with input/output/elapsed_ms |
| `ingested_documents` | MarkItDown-converted files and URLs |
| `markitdown_audit` | Conversion success/failure with file hash and duration |
| `jobs` + `job_runs` | Async job queue |

---

## Request Lifecycle

### Chat message
```
Discord → POST /ask → http_server.py
  → _try_deliver_reply() → not a selection reply
  → brain_pipeline.py
  → tool_registry.execute() → no match
  → assistant_tools dispatch → no match
  → load history + inject memory
  → POST Ollama /v1/chat/completions
  → save to BrainDB → return response → Discord
```

### Tool command (`!scrape`, `!browse`, etc.)
```
Discord → POST /ask → http_server.py
  → _try_deliver_reply() → not a selection reply
  → brain_pipeline.py
  → tool_registry.execute() → no match
  → assistant_tools dispatch → matched handler
  → external call (Pinchtab / scrape / etc.)
  → return result → Discord
```

### Coding task (`!task`)
```
Discord → POST /ask → http_server.py
  → _try_deliver_reply() → not a selection reply
  → brain_pipeline.py
  → tool_registry.execute() → matched: coding-agent
  → coding_agent.handle_task_tool()
    → skill_injector: score skills
    → if ≥5 candidates: POST /notify (menu) → wait for reply
    → build SPEC.md
    → task_router → LM Studio 14B or Pi Ollama
    → POST /copilot/task → VS Code bridge
    → POST /notify (done) → Discord
```

### Skill selection reply
```
Discord → POST /ask (text = "1,3")
  → http_server.py
  → _try_deliver_reply("1,3") → consumed → return "✅ Selection received."
  (coding_agent thread unblocked, continues with selected skills)
```

### Long-running task (`!android`, `!task`)
```
Discord → POST /ask → spawn async loop
  → POST /notify with incremental updates
  ← Discord bot polls GET /notify every 1s
  → Discord sends each update as it arrives
```

---

## Streaming Architecture

Jeeves uses a lightweight poll-based streaming model:

1. Long-running tools POST updates to `POST /notify?server_id=<id>&message=<text>`
2. HTTP daemon queues them in a per-server `deque`
3. Discord bot polls `GET /notify?server_id=<id>` every 1 second
4. Queued message is returned and immediately sent to the Discord channel
5. Empty queue returns 200 with no body (bot keeps polling)

---

## VS Code Bridge

Runs on your **Windows PC** at port 5055. Exposes file I/O and shell execution to the Pi.

```
Pi (coding_agent) → POST http://192.168.1.153:5055/copilot/task
                         → creates project folder
                         → writes SPEC.md
                         → writes .continue/autoprompt.md
                         → opens VS Code (--new-window)
                         → writes pending_prompt.txt
                               ↓
                     extension.js polls pending_prompt.txt every 1s
                               ↓
                     Continue (VS Code, Agent mode)
                     → Qwen 14B via LM Studio :1234
                     → reads SPEC.md, creates all files, runs, fixes errors
```

---

## Model Routing (`task_router.py`)

```
route_task() called
  ↓
probe http://PC_IP:1234/v1/models  (2s timeout, cached 30s)
  ↓
reachable  → LM Studio → Qwen 14B Coder (qwen2.5-coder-14b-instruct)
unreachable → Pi Ollama → qwen2.5:1.5b (core) / qwen2.5-coder:3b (coder)
```

---

## Browser Tool (Pinchtab)

A Go binary that wraps Chromium via the DevTools Protocol. Runs as a systemd service on the Pi, binding to `127.0.0.1:9867` only — not reachable from your LAN.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Liveness check |
| `/navigate` | POST `{url}` | Go to URL |
| `/text` | GET | Extract readable page text (~800 tokens) |
| `/snapshot` | GET `?format=text&filter=interactive` | Accessibility tree with element refs |
| `/action` | POST `{kind, ref, ...}` | click / fill / press / scroll / hover |
| `/screenshot` | GET `?quality=80` | JPEG screenshot as base64 |
| `/tabs` | GET | List open tabs |
| `/evaluate` | POST `{expression}` | Run JavaScript |

---

## File Layout

```
/mnt/storage/pi-assistant/
  assistant/
    brain.py                  ← AssistantBrain entry point
    brain_core.py             ← tool dispatch + pipeline orchestration
    brain_db.py               ← SQLite BrainDB (WAL mode)
    brain_pipeline.py         ← tool registry dispatch + LLM call
    gemini_agent.py           ← !android autonomous builder
    document_ingest.py        ← MarkItDown skill (ingest + store)
    markitdown_command.py     ← !markdownify / !mdoc Discord handler
    http_server.py            ← HTTP daemon :8001 (v2.1.2)
    memory_loader.py          ← memory note injection
    mcp_registry.py           ← MCP tool catalogue singleton
    mcp_client.py             ← MCP tool executor + BrainDB logger
    task_router.py            ← multi-provider model routing
    tool_registry.py          ← priority-ordered tool dispatch (NEW)
    coding_agent.py           ← !task orchestration + SPEC.md + skills
  tools/
    assistant_tools.py        ← classic tool dispatcher
    skill_injector.py         ← skill scoring + injection + interactive selection
    skills_manager.py         ← !skill commands (Discord-facing)
    browser/browser_tools.py
    email/email_tools.py
    calendar/calendar_tools.py
    cast/chromecast_tools.py
    design/design_tools.py
    vscode/vscode_tools.py
  skills/
    antigravity-awesome-skills/skills/   ← 978 community skills
    claude-skills/
    claude-scientific-skills/scientific-skills/
    superpowers/skills/
    ui_ux_pro_max_skill/skills/
    custom/                              ← your own skills
  data/
    jeeves.db                 ← SQLite BrainDB

PC (Windows):
  G:\Jeeves\vscode-bridge\
    server.js                 ← Node bridge :5055 (v4.4)
    extension.js              ← VS Code extension watcher (v2.2)
  C:\Users\Jerry\.continue\
    config.yaml               ← Continue model config
  LM Studio models\
    Qwen2.5-Coder-14B Q4_K_M  ← primary coding agent (8.99 GB)
    Qwen2.5-Coder-3B  Q4_K_M  ← inline autocomplete (2.1 GB)
```

---

## Security Notes

| Concern | Mitigation |
|---------|-----------| 
| VS Code bridge on LAN | Trusted LAN only; no auth needed for personal use |
| LM Studio on LAN | Trusted LAN only; enable "Serve on Local Network" intentionally |
| Pinchtab | Binds `127.0.0.1` — not reachable from LAN |
| Gemini API key | Environment variable; never in code or git |
| Discord bot token | `.env` file, `.gitignore`d |
| Shell execution (`!vscode run`) | Intentional — Jeeves is a trusted personal tool |
| SQLite DB | Local file, no network exposure |
