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
│             discord_bot.py — strips prefix, routes               │
│             POST /ask  ──────────────────────────────────────►    │
│             GET  /notify  (polls every 1s, streams to channel)    │
└───────────────────────────┬───────────────────────────────────────┘
                            │ HTTP :8001
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│             pi-assistant.service  (HTTP daemon)                   │
│             http_server.py — ThreadingHTTPServer                  │
│                                                                   │
│   /ask ──► brain_core.py ──► tool dispatch ──► brain pipeline    │
│   /notify ──► per-server streaming queue (deque)                  │
└──────┬────────────────────────────────────────────────────────────┘
       │
       ├── !email / !calendar ──────► IMAP / Google Calendar API
       │
       ├── !design ────────────────► design_tools.py
       │                              └── Ollama gemma2:2b
       │
       ├── !cast ──────────────────► chromecast_tools.py (pychromecast)
       │
       ├── !task / !vscode ────────► VS Code Bridge  (PC :5055)
       │                              ├── /write  /read  /run  /ls  /open
       │                              └── /copilot/task
       │                                    └── writes SPEC.md + pending_prompt.txt
       │                                          │
       │                                          ├──► Continue extension (default)
       │                                          │      └── Qwen 14B via LM Studio :1234
       │                                          ├──► cn CLI (--cn flag)
       │                                          │      └── Qwen 14B via LM Studio :1234
       │                                          └──► GitHub Copilot (--copilot flag)
       │
       ├── !browse ────────────────► tools/browser/browser_tools.py
       │                              └── HTTP localhost:9867
       │                                    └── Pinchtab (Go binary, systemd)
       │                                          └── Chromium headless
       │
       ├── !android ───────────────► assistant/gemini_agent.py
       │                              ├── POST api.generativeai.google.com (Gemini 2.0 Flash)
       │                              ├── parse ### FILE: blocks from response
       │                              └── POST VS Code Bridge /write  (one file at a time)
       │
       └── !markdownify ───────────► assistant/document_ingest.py
                                      ├── tools/markitdown/convert.py
                                      ├── markitdown.MarkItDown.convert_stream()
                                      └── BrainDB  ingested_documents table

Model Routing (task_router.py):
  LM Studio online  (PC :1234)  →  Qwen 14B Coder  (primary)
  LM Studio offline             →  Pi Ollama        (fallback)
```

---

## Component Details

### pi-discord-bot.service
- `discord_bot.py` — asyncio, listens on all configured servers simultaneously
- Strips activation word, POSTs `{server_id, channel, user, content}` to `/ask`
- Polls `GET /notify?server_id=<id>` every 1 second — delivers streamed output to the right channel
- Handles Discord file attachments (reads bytes, sends as base64 in payload)

### pi-assistant.service
- `http_server.py` — stdlib `ThreadingHTTPServer` on port 8001
- Thread-per-request; SQLite is WAL mode for safe concurrent access
- `/ask` → `brain_core.py` → tool dispatch, then brain pipeline if no tool matched
- `/notify` → drains a per-server deque (returns immediately with queued message or empty)

### Tool Dispatcher (`tools/assistant_tools.py`)
Central router. Every tool import is wrapped in a try/except — missing dependencies stub out silently and Jeeves keeps running.

Each handler returns `(handled: bool, response: str)`. Dispatcher tries in order and returns on first match.

Key handlers:

| Handler | Trigger | Module |
|---------|---------|--------|
| `handle_email_tool` | `!email` | `tools/email/email_tools.py` |
| `handle_calendar_tool` | `!addevent`, `!getevents` | `tools/calendar/calendar_tools.py` |
| `handle_design_tool` | `!design` | `tools/design/design_tools.py` |
| `handle_cast_tool` | `!cast` | `tools/cast/chromecast_tools.py` |
| `handle_vscode_tool` | `!vscode`, `!task` | `tools/vscode/vscode_tools.py` |
| `handle_browse_tool` | `!browse`, natural lang | `tools/browser/browser_tools.py` |
| `handle_android_command` | `!android` | `assistant/gemini_agent.py` |
| `handle_markitdown_command` | `!markdownify`, `!mdoc` | `assistant/markitdown_command.py` |

### Brain Pipeline (`assistant/brain_core.py` + `brain_pipeline.py`)
Runs when no tool claims the message:
1. Load conversation history from BrainDB (token-budgeted, newest-first selection)
2. Inject relevant memory notes (keyword overlap scoring)
3. POST to Ollama `qwen2.5:1.5b` via `/v1/chat/completions`
4. Save assistant reply to BrainDB

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
| `ingested_documents` | MarkItDown-converted files and URLs (full Markdown) |
| `markitdown_audit` | Conversion success/failure with file hash and duration |
| `jobs` + `job_runs` | Async job queue |

---

## Request Lifecycle

### Chat message
```
Discord → POST /ask → brain_core.py
  → tool dispatch (no match)
  → load history + inject memory
  → POST Ollama /v1/chat/completions
  → save to BrainDB
  → return response → Discord
```

### Tool command
```
Discord → POST /ask → brain_core.py
  → tool dispatch → matched handler
  → external call (Pinchtab / VS Code bridge / etc.)
  → return result → Discord
```

### Long-running task (`!android`, `!task`)
```
Discord → POST /ask → brain_core.py
  → spawn async loop
  → POST /notify with incremental updates
  ← Discord bot polls GET /notify every 1s
  → Discord sends each update as it arrives
```

---

## Streaming Architecture

Jeeves uses a lightweight poll-based streaming model to avoid websocket complexity:

1. Long-running tools POST updates to `POST /notify?server_id=<id>&message=<text>`
2. HTTP daemon queues them in a per-server `deque`
3. Discord bot polls `GET /notify?server_id=<id>` every 1 second
4. Queued message is returned and immediately sent to the Discord channel
5. Empty queue returns 200 with no body (bot keeps polling)

This lets Jeeves stream `[1/7] Writing structure…` → `[2/7] Data layer…` → etc. as each phase completes.

---

## VS Code Bridge

Runs on your **Windows PC** at port 5055. Exposes file I/O and shell execution to the Pi.

```
Pi (any tool)  →  POST http://192.168.1.153:5055/write
                        /read
                        /run
                        /ls
                        /open
                        /copilot/task  → writes SPEC.md + pending_prompt.txt
                                              ↓
                                    extension.js polls pending_prompt.txt every 1s
                                              ↓
                                    ┌─────────────────────────────────┐
                                    │  Continue (default)             │
                                    │  continue.focusContinueInput    │
                                    │  → Qwen 14B via LM Studio :1234 │
                                    ├─────────────────────────────────┤
                                    │  cn CLI (--cn flag)             │
                                    │  fully autonomous, no clicks    │
                                    │  → Qwen 14B via LM Studio :1234 │
                                    ├─────────────────────────────────┤
                                    │  GitHub Copilot (--copilot)     │
                                    │  workbench.action.chat.open     │
                                    └─────────────────────────────────┘
```

Configure the PC IP in `coding_agent.py`:
```python
VSCODE_HOST  = "http://192.168.1.153:5055"
LMSTUDIO_URL = "http://192.168.1.153:1234"   # task_router.py
```

---

## Model Routing (`task_router.py`)

Automatic provider selection at runtime:

```
route_task() called
  ↓
probe http://PC_IP:1234/v1/models  (2s timeout, cached 30s)
  ↓
reachable  →  LM Studio  →  Qwen 14B Coder  (qwen2.5-coder-14b-instruct)
unreachable → Pi Ollama  →  qwen2.5:1.5b (core) / qwen2.5-coder:3b (coder)
```

Model assignments per task type:

| Task Type | PC Model | Pi Fallback |
|-----------|----------|-------------|
| `core` | qwen2.5-coder-14b-instruct | qwen2.5:1.5b |
| `coder` | qwen2.5-coder-14b-instruct | qwen2.5-coder:3b |
| `reasoner` | qwen2.5-coder-14b-instruct | qwen2.5:1.5b |
| `summarizer` | qwen2.5-coder-3b-instruct | qwen2.5:0.5b |

---

## Browser Tool (Pinchtab)

A Go binary that wraps Chromium via the DevTools Protocol. Runs as a systemd service on the Pi. No Python browser driver needed.

```
tools/browser/browser_tools.py
  → HTTP 127.0.0.1:9867
  → Pinchtab (pinchtab.service)
  → Chromium headless
```

Key endpoints:

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

## Android Builder (Gemini Agent)

Autonomous Android app builder that calls the Gemini API directly from the Pi and writes generated files to the PC via the VS Code bridge.

```
assistant/gemini_agent.py
  → POST generativelanguage.googleapis.com (Gemini 2.0 Flash, free tier)
  → parse ### FILE: <path>\n<content> blocks from response
  → POST http://192.168.1.153:5055/write  (one POST per file)
  → POST /notify  (progress update to Discord after each phase)
```

---

## MarkItDown Integration

Universal document ingestion. Converts any file or URL to Markdown and stores it in BrainDB.

```
assistant/document_ingest.py
  → tools/markitdown/convert.py
  → markitdown.MarkItDown.convert_stream()
  → INSERT INTO ingested_documents
  → INSERT INTO markitdown_audit
  → log_tool_call() in tool_audit
```

Supports: PDF, Word (.docx), PowerPoint (.pptx), Excel (.xlsx), HTML, plain text, images (OCR), audio (transcription), YouTube transcripts, ZIP, EPubs.

---

## File Layout

```
/mnt/storage/pi-assistant/
  assistant/
    brain.py                  ← AssistantBrain entry point
    brain_core.py             ← tool dispatch + pipeline orchestration
    brain_db.py               ← SQLite BrainDB (WAL mode)
    brain_pipeline.py         ← LLM call, memory injection
    gemini_agent.py           ← !android autonomous builder
    document_ingest.py        ← MarkItDown skill (ingest + store)
    markitdown_command.py     ← !markdownify / !mdoc Discord handler
    http_server.py            ← HTTP daemon :8001
    memory_loader.py          ← memory note injection
    task_router.py            ← multi-provider model routing (LM Studio / Ollama)
    coding_agent.py           ← !task orchestration + SPEC.md generation
  tools/
    assistant_tools.py        ← central tool dispatcher
    browser/
      browser_tools.py        ← Pinchtab HTTP wrapper
    email/email_tools.py
    calendar/calendar_tools.py
    cast/chromecast_tools.py
    design/design_tools.py
    vscode/vscode_tools.py
  vscode-bridge/              ← runs on Windows PC
    server.js                 ← Express HTTP bridge :5055
    extension.js              ← VS Code extension (Continue / Copilot injection)
  data/
    jeeves.db                 ← SQLite BrainDB

PC (Windows):
  G:\Jeeves\vscode-bridge\
    server.js                 ← Node bridge :5055
    extension.js              ← VS Code extension watcher
  C:\Users\Jerry\.continue\
    config.yaml               ← Continue model config (Qwen 14B + Pi fallback)
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
