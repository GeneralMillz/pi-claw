# MCP Layer

**Model Context Protocol integration for Jeeves**

This document covers the MCP layer added to Jeeves in March 2026 — how it works, how it fits into the existing architecture, the full tool catalogue, agent mode, and how to extend it.

---

## What MCP Adds

Before MCP, every Jeeves tool required an explicit `!command` prefix. You told Jeeves *how* to do something.

With MCP, you tell Jeeves *what* you want in plain English and it figures out the sequence of tools to call.

```
Before:  !scrape search RTX 5090 price
         !scrape price https://www.bhphotovideo.com/...
         (manual, two steps)

After:   jeeves agent: find me the cheapest RTX 5090 right now
         (Jeeves searches, scrapes prices, and returns a summary)
```

The `!` commands are completely unchanged and will always work. MCP is an additive layer on top.

---

## Architecture

```
assistant/
├── mcp_registry.py     ← Tool catalogue + server descriptors
└── mcp_client.py       ← Tool executor + BrainDB logger

task_router.py          ← Agent mode detection + orchestration loop
```

### Request flow for agent mode

```
Discord: "jeeves agent: <request>"
         │
         ▼
task_router.detect_agent_mode()         ← detects "jeeves agent:" prefix
         │
         ▼
task_router._run_agent_loop()
         │
         ├── get_registry().to_llm_catalogue()   ← build tool list
         │
         ├── PC: LM Studio Qwen2.5-Coder-14B     ← model decides what to call
         │         (function calling mode)
         │
         ├── model returns tool_calls []
         │         │
         │         ▼
         │   MCPClient.call(tool_name, args)      ← Pi executes each tool
         │         │
         │         ▼
         │   result fed back to model             ← model sees tool output
         │
         └── model returns final text → Discord
```

Every tool call in the loop is logged to `tool_audit` in BrainDB regardless of success or failure.

---

## Agent Mode Triggers

| Trigger | Example |
|---------|---------|
| `jeeves agent: <request>` | `jeeves agent: check my open tasks` |
| `jeeves do: <request>` | `jeeves do: search for RTX 5090 price and save it` |

Agent triggers are configured in `config.json` under `mcp.agent_triggers` and in `task_router.py`'s `_AGENT_PREFIXES` tuple. Adding a new trigger requires updating both.

---

## Fallback Behavior

If the PC is offline or LM Studio is unreachable, the agent loop detects `ConnectionError` on the first call and immediately falls back to the Pi's `qwen2.5:1.5b` reasoner. The response will be slower and won't use tools, but Jeeves will not crash or return an error to Discord.

The fallback model is configurable: `config.json → mcp.fallback_model`.

---

## config.json MCP Block

```json
"mcp": {
  "enabled": true,
  "agent_model": "qwen2.5-coder-14b-instruct",
  "agent_url": "http://192.168.1.153:1234",
  "max_rounds": 5,
  "round_timeout_sec": 120,
  "fallback_model": "qwen2.5:1.5b",
  "agent_triggers": [
    "jeeves agent:",
    "jeeves do:"
  ]
}
```

| Key | Description |
|-----|-------------|
| `enabled` | Master switch. Set `false` to disable agent mode entirely. |
| `agent_model` | LM Studio model name for tool-calling |
| `agent_url` | LM Studio base URL on the PC |
| `max_rounds` | Max tool-call iterations before the loop terminates |
| `round_timeout_sec` | Per-round timeout for LM Studio calls |
| `fallback_model` | Pi Ollama model used when PC is offline |
| `agent_triggers` | Prefixes that trigger agent mode |

---

## Tool Catalogue

All tools are registered in `mcp_registry.py` via `_register_builtin_tools()` and executed in `mcp_client.py`.

### Scrape Server (`server: "scrape"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `scrape_url` | Fetch and extract main text content from a URL | `url` |
| `web_search` | DuckDuckGo search, ad-filtered, returns top results | `query` |

**scrape_url optional args:** `selector` (CSS selector), `mode` (`content` or `price`)

### Browser Server (`server: "browser"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `browser_navigate` | Open a URL in the browser via Pinchtab | `url` |
| `browser_click` | Click an element by CSS selector | `selector` |

### Memory Server (`server: "memory"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `memory_save` | Save a note to BrainDB long-term memory | `note` |
| `memory_recall` | Recall notes relevant to a topic | `query` |

**memory_save optional args:** `tags` (comma-separated), `server_id`

### Filesystem Server (`server: "filesystem"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `file_read` | Read file contents from Pi or PC | `path` |
| `file_write` | Write a file on the Pi (snapshots first) | `path`, `content` |
| `file_list` | List files in a directory | `path` |

**file_read / file_list optional args:** `target` (`pi` or `pc`), `lines` (e.g. `"10-50"`)

> `file_write` automatically snapshots the existing file to BrainDB before overwriting. This is non-negotiable and cannot be disabled.

### Coding Server (`server: "coding"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `coding_task` | Submit a task to the coding agent → writes SPEC.md → triggers Continue/Cursor | `prompt` |

**coding_task optional args:** `project` (creates project if missing), `task_type` (`coder` or `reasoner`)

### Tasks Server (`server: "tasks"`)

| Tool | Description | Required Args |
|------|-------------|---------------|
| `task_create` | Create a task in BrainDB task queue | `title` |
| `task_list` | List open tasks | — |

**task_create optional args:** `description`, `priority` (1=urgent, 10=low), `project`

---

## Tool Call Logging

Every MCP tool call — whether triggered by agent mode or called directly — is logged to the `tool_audit` table in BrainDB:

```sql
SELECT tool, input, output, elapsed_ms, created_at
FROM tool_audit
ORDER BY created_at DESC
LIMIT 20;
```

From Discord: `!audit` shows the last 20 entries.

Programmatically:
```python
from assistant.brain_db import get_db
calls = get_db().get_recent_tool_calls(limit=20)
```

---

## Calling Tools Directly

You can call any MCP tool directly from Python without going through agent mode:

```python
from assistant.mcp_client import get_client

client = get_client(server_id="your_discord_server_id")

# Scrape a URL
result = client.call("scrape_url", {"url": "https://news.ycombinator.com"})
print(result.data)          # extracted content
print(result.elapsed_ms)    # how long it took

# Save to memory
result = client.call("memory_save", {
    "note": "RTX 5090 MSRP is $1,999",
    "tags": "hardware,gpu"
})

# List tools
from assistant.mcp_registry import get_registry
for tool in get_registry().list_tools():
    print(tool.name, "→", tool.description)
```

---

## Inspecting the Registry

```python
from assistant.mcp_registry import get_registry

registry = get_registry()

# Human-readable summary
print(registry.summary())

# LLM-ready catalogue (for injection into any model)
catalogue = registry.to_llm_catalogue()

# Filter by server or tag
web_tools = registry.list_tools(server="scrape")
memory_tools = registry.list_tools(tag="memory")

# Disable a tool temporarily
registry.disable_tool("browser_click")
```

---

## Adding a New Tool

**1. Register it in `mcp_registry.py` inside `_register_builtin_tools()`:**

```python
registry.register_tool(
    name="weather_get",
    description="Get the current weather for a city.",
    server="weather",          # auto-creates server if new
    parameters={
        "city": {
            "type": "string",
            "description": "City name",
            "required": True,
        },
        "units": {
            "type": "string",
            "description": "metric or imperial",
            "required": False,
        },
    },
    tags=["weather", "lookup"],
)
```

**2. Add a dispatch case in `mcp_client.py` inside `_dispatch()`:**

```python
if name == "weather_get":
    return self._weather_get(args)
```

**3. Implement the handler method in `MCPClient`:**

```python
def _weather_get(self, args: Dict) -> str:
    city  = args["city"]
    units = args.get("units", "imperial")
    # your implementation here
    return f"Weather in {city}: 72°F, partly cloudy"
```

That's it. The tool is now available to agent mode, callable directly, and logged to BrainDB automatically.

---

## Files Reference

| File | Purpose |
|------|---------|
| `assistant/mcp_registry.py` | `MCPRegistry`, `MCPTool`, `MCPServer` classes. Tool catalogue singleton. |
| `assistant/mcp_client.py` | `MCPClient`, `MCPResult`. Executes tools, logs to BrainDB. |
| `assistant/task_router.py` | `detect_agent_mode()`, `_run_agent_loop()`, `_call_lm_studio()`. Orchestration. |
| `config.json` | `mcp` block — model, URL, timeouts, triggers. |

---

## Known Limitations

- **Local model function-calling reliability** — Qwen2.5-Coder-14B handles tool calls well but occasionally fails to parse complex nested arguments. If a tool call fails, the loop continues to the next round.
- **No streaming in agent mode** — the full agent loop completes before the Discord response is sent. Long multi-tool chains can take 60-90 seconds. Discord streaming for agent mode is a planned improvement.
- **Browser tools require Pinchtab** — `browser_navigate` and `browser_click` depend on the Pinchtab Go binary being running on the Pi. They degrade gracefully if unavailable.
- **PC tools require VS Code bridge** — `file_read`/`file_list` with `target: pc` require the VS Code bridge running on the PC at `:5055`.
