# Jeeves — Architecture

---

## Request Lifecycle

```
1. User types: "jeeves !task build a flask app"

2. Discord bot (core.py → on_message):
   - Verify server is in SERVER_CONFIG
   - Verify channel is in allowed_channels
   - Check rate limit
   - extract_prompt() → strips activation word → "!task build a flask app"
   - register_stream_channel() → tracks which channel to send notify updates to
   - _process_and_respond() → shows typing indicator

3. call_daemon_with_retry() → POST http://127.0.0.1:8001/ask
   { user, server_id, channel_name }

4. HTTP daemon (http_server.py):
   → brain.process(user_text, server_id, channel)

5. Brain (brain_pipeline.py):
   → tools.execute(user_text)
   → "!task" matched → handle_task_tool()
   → Spawns background thread, returns immediately:
      "⚙️ Task started — streaming updates incoming..."

6. HTTP daemon returns {"type": "tool", "content": "⚙️ Task started..."}

7. Discord bot → channel.send("⚙️ Task started...")

8. Background thread (coding_agent.py):
   → _notify(server_id, "📋 Planning...") → POST /notify → push to queue
   → route_task() → Qwen generates plan
   → _notify(server_id, "✅ Plan ready")
   → writes SPEC.md via VS Code bridge
   → POST /copilot/task → VS Code opens

9. notify_poller (asyncio task in core.py):
   → every 2s: GET /notify?server_id=xxx
   → pops queue → channel.send() for each message
```

---

## File Map

```
assistant/
  brain.py              AssistantBrain — loads config, tools, pipeline
  brain_pipeline.py     BrainPipeline — history, facts, memory, LLM, history save
  http_server.py        HTTP daemon :8001 — /ask + /notify push + /notify poll
  memory_loader.py      Loads memory/<id>.md into system prompt
  audit_log.py          JSONL tool call audit log
  summarizer.py         Gemma2 summarization for design output
  task_router.py        Routes tasks to specialist models

tools/
  assistant_tools.py    Main dispatcher — _TOOL_TABLE + NL triggers
  coding_agent.py       Plan → SPEC.md → Copilot handoff + streaming
  vscode/
    vscode_tools.py     VSCodeBridge — HTTP client to PC bridge
  calendar/
    assistant_calendar.py   Google Calendar API
    calendar_nlp.py         NL date parsing
  email/
    email_tools.py      IMAP read + SMTP send
  design/
    design_tools.py     UI/UX design system generator
  sitekit/
    sitekit_tools.py    SiteKit automation
  cast/
    chromecast_tools.py pychromecast wrapper
  discord/
    core.py             Client, on_message, notify_poller
    daemon_client.py    HTTP client to :8001
    routing.py          Channel checks, activation word, rate limit
    message_utils.py    Output clamping for Discord limits
    typing_indicator.py "Bot is typing..." while waiting
    config_loader.py    Loads all server configs at startup
    logging.py          Debug helpers

core/
  history.py            Per-server conversation history (JSON files)
  personas.py           build_system_message()
  facts.py              Fact file loader + keyword scorer
  sanitize.py           LLM output cleaner
  config.py             Server config loader

memory/
  personal.example.md   Template — copy to YOUR_SERVER_ID.md

config/
  servers/              Per-server JSON configs
  personas/             Persona text files
  model_prefs.json      Default model settings

tasks/
  morning_briefing.py   Daily 8am briefing (add to cron to activate)

logs/
  tool_audit.jsonl      One JSON line per tool call
```

---

## Streaming Architecture

```
┌─────────────────────────────────────┐
│  coding_agent.py (background thread) │
│  _notify(server_id, "📋 Planning")   │
│    └─→ POST /notify                  │
└──────────────────┬──────────────────┘
                   ▼
┌─────────────────────────────────────┐
│  http_server.py                      │
│  push_notify() → _notify_queues[]    │
│    (in-memory deque, thread-safe)    │
└──────────────────┬──────────────────┘
                   ▼
┌─────────────────────────────────────┐
│  core.py — notify_poller()           │
│  asyncio task, polls every 2s        │
│  GET /notify?server_id=xxx           │
│    → pop queue → channel.send()      │
└─────────────────────────────────────┘
```

Polling (not SSE/WebSocket) is used because the daemon is synchronous stdlib HTTPServer while the Discord bot is asyncio. Polling is the simplest reliable bridge between the two.

---

## Brain Pipeline

```
User message
     │
     ▼ Tool check (fast path — no LLM)
     │ (if not a tool)
     ▼
load_history_with_token_budget()
     ▼
build_system_message()      ← persona file + channel tone
     ▼
get_relevant_facts()        ← keyword scoring (if enabled)
     ▼
memory_block(server_id)     ← reads memory/<id>.md
     ▼
Ollama POST /v1/chat/completions
  model: qwen2.5:1.5b
  max_tokens: 128 (short) | 250 (narrative)
  timeout: 90s
     ▼
sanitize_output()
     ▼
save_history()
```

---

## Task Router

```python
route_task(prompt, task_type)
  "reasoner" → qwen2.5:1.5b   (planning, architecture)
  "coder"    → qwen2.5-coder:3b (code generation)
  "core"     → qwen2.5:1.5b   (general)
```

Models load on-demand via Ollama. First call after idle may add 10-30s for model load; subsequent calls are fast.

---

## VS Code Bridge Protocol

Simple JSON over HTTP on port 5055. No authentication (LAN only — do not expose to internet).

```
POST /write  { "path": "C:\\projects\\app\\main.py", "content": "..." }
→ { "success": true, "message": "Written: ..." }

POST /copilot/task  { "task": "...", "project_path": "C:\\projects\\app", "context": "..." }
→ writes SPEC.md, opens VS Code, returns { "success": true }
```

All error handling is done in `VSCodeBridge` (Python) and formatted for Discord output.
