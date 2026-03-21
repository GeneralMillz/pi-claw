# 🔧 Tool Registry

The **Tool Registry** (`assistant/tool_registry.py`) is the priority-ordered dispatch layer that sits at the top of `brain_pipeline.py`. It replaces the broken `self.tools.execute()` pattern that caused all `!task` commands to silently fall through to the LLM.

---

## Why It Exists

Before the Tool Registry, every `!task` command was supposed to be intercepted and handed to `coding_agent.py`. In practice, `self.tools` was never defined anywhere in the codebase — so every message went directly to the LLM chat. The fix: a proper singleton registry that `brain_pipeline.py` imports and calls.

---

## How It Works

```
brain_pipeline.py
  ↓
registry.execute(user_text, brain, server_id)
  ↓
iterate handlers in priority order (lowest number = highest priority)
  ↓
first handler whose trigger matches user_text → called
  ↓
returns (handled=True, response)  or  (handled=False, "")
  ↓
if not handled → fall through to assistant_tools.py dispatch
  ↓
if still not handled → LLM chat
```

---

## Built-in Handlers

| Priority | Name | Triggers |
|----------|------|----------|
| 10 | `coding-agent` | `!task`, `build me`, `create a`, `make a`, `write a`, `make me a`, `build a`, `code a`, `create me` |
| 20 | `tools-list` | `!tools`, `!help tools`, `list tools` |

Matching is **case-insensitive substring** — `user_text.lower()` is checked against each trigger string.

---

## Adding a New Tool

### Option A — Inline block in `tool_registry.py`

```python
@registry.tool(triggers=["!deploy", "deploy to"], name="deploy-agent", priority=15)
def deploy_handler(text: str, brain, server_id: str):
    # text    = full original message
    # brain   = AssistantBrain instance (has .db, .config, etc.)
    # server_id = Discord guild ID string
    return True, "Deploying..."
```

Add this block anywhere in `tool_registry.py` below the `registry = ToolRegistry()` line.

### Option B — Drop-in `*_tool.py` file

Create `/mnt/storage/pi-assistant/tools/my_feature_tool.py`:

```python
from assistant.tool_registry import registry

@registry.tool(triggers=["!myfeature"], name="my-feature", priority=30)
def my_feature_handler(text: str, brain, server_id: str):
    # your logic
    return True, "Done!"
```

`registry.load_all(tools_dir)` in `tool_registry.py` auto-discovers all `*_tool.py` files. No changes to `brain_pipeline.py` ever needed.

### Option C — Imperative registration

```python
from assistant.tool_registry import registry

def my_handler(text, brain, server_id):
    return True, "result"

registry.register(
    triggers=["!mycommand"],
    handler=my_handler,
    name="my-command",
    description="Does my thing",
    priority=25,
)
```

---

## API Reference

### `ToolRegistry`

```python
registry = ToolRegistry()

# Register a handler
registry.register(triggers, handler, name="", description="", priority=50)

# Decorator form
@registry.tool(triggers=[...], name="", description="", priority=50)
def handler(text, brain, server_id): ...

# Auto-discover *_tool.py files in a directory
registry.load_all(tools_dir: Path)

# Dispatch — called by brain_pipeline.py
handled, response = registry.execute(text, brain, server_id)

# List for !tools command
tools = registry.list_tools()  # list of {name, triggers, description, priority}
```

### `registry.execute()` contract

- Returns `(True, response_str)` if a handler claimed the message
- Returns `(False, "")` if no handler matched
- Handlers must never raise — exceptions are caught and logged, returns `(True, "[error message]")`

---

## Priority Guidelines

| Priority | Use case |
|----------|---------|
| 1–9 | Reserved for future system-level overrides |
| 10 | Coding pipeline (highest current priority) |
| 11–19 | Tools that must intercept before coding-agent if overlap exists |
| 20–29 | Utility / info commands |
| 30–49 | Feature tools |
| 50+ | Low-priority / catch-all handlers |

---

## Inspecting the Registry

From Discord:
```
!tools
```

From the Pi shell:
```bash
python3 -c "
from assistant.tool_registry import registry
for t in registry.list_tools():
    print(t['priority'], t['name'], t['triggers'])
"
```

---

## File Location

```
/mnt/storage/pi-assistant/assistant/tool_registry.py
```

Imported by:
```
assistant/brain_pipeline.py   ← calls registry.execute()
assistant/http_server.py      ← imports coding_agent for deliver_reply
tools/coding_agent.py         ← registered as "coding-agent" handler
```
