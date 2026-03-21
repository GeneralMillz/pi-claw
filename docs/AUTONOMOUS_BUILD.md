# Jeeves Autonomous Build System

> **Full documentation for the Continue + LM Studio autonomous development pipeline.**
> Covers the VS Code Bridge, skill injection, Continue agent integration, local LLM setup, and how every component connects.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
  - [Tool Registry](#tool-registry-tool_registrypy)
  - [Coding Agent — Pi (`coding_agent.py`)](#coding-agent-coding_agentpy)
  - [Skill Injector (`skill_injector.py`)](#skill-injector-skill_injectorpy)
  - [VS Code Bridge — PC (`server.js`)](#vs-code-bridge-serverjs)
  - [VS Code Extension (`extension.js`)](#vs-code-extension-extensionjs)
  - [Continue Config (`config.yaml`)](#continue-config-configyaml)
- [End-to-End Flow](#end-to-end-flow)
- [Local LLM Setup](#local-llm-setup)
- [Bridge Endpoints](#bridge-endpoints)
- [File Reference](#file-reference)
- [Configuration](#configuration)
- [Adding a New Project Type](#adding-a-new-project-type)
- [Troubleshooting](#troubleshooting)

---

## Overview

When you send `!task build a mega man game` in Discord, Jeeves orchestrates an autonomous build pipeline that:

1. Routes the command through the **Tool Registry** (priority dispatch — no LLM involved)
2. Scores the 978+ skill library and optionally asks you which skills to inject via Discord
3. Plans the project using a fast local model on the Pi (or LM Studio 14B if PC is on)
4. Writes a full `SPEC.md` to the PC via the VS Code Bridge
5. Opens VS Code to the project folder
6. Injects an autonomous build prompt into Continue
7. Continue + Qwen 14B builds the entire project — creating files, running code, fixing errors — without any human input

This is a self-hosted replacement for GitHub Copilot Workspace, running entirely on your local network.

---

## Architecture

```
Discord (!task)
    │
    ▼
Pi — brain_pipeline.py
    │  tool_registry.execute()
    │  matched: "coding-agent" (priority 10)
    │
    ▼
Pi — coding_agent.handle_task_tool()
    │
    ├── skill_injector.find_skills_for_task()
    │     ├── score 978+ skills against project type keywords
    │     ├── ≥5 candidates → POST /notify (Discord menu)
    │     │                  → wait up to 60s for reply
    │     │                  → timeout → auto top-3
    │     └── inject selected SKILL.md content into SPEC.md
    │
    ├── _load_uncodixfy()  → append UI rules if uncodixfy.md present
    │
    ├── task_router.route_task()
    │     ├── probe PC :1234 (cached 30s)
    │     ├── PC online  → Qwen 14B Coder (LM Studio)
    │     └── PC offline → qwen2.5:1.5b (Pi Ollama)
    │
    ├── _build_spec_md()   → full SPEC.md with type contract + skills
    │
    └── POST /copilot/task → server.js (PC :5055)
          ├── mkdir G:\Jeeves\projects\<slug>
          ├── write SPEC.md
          ├── write .continue\autoprompt.md
          ├── code --new-window "<project_path>"
          ├── write pending_prompt.txt (immediately)
          └── re-write pending_prompt.txt after 8s (new-window safety net)
                │
                ▼
        extension.js (VS Code, v2.2)
          ├── startup scan: detect files written before window loaded
          ├── detect autoprompt.md OR pending_prompt.txt
          ├── wait up to 30s for Continue to be active
          └── paste + submit to Continue
                │
                ▼
        Continue + Qwen 14B (LM Studio :1234)
          ├── read_file SPEC.md
          ├── create_new_file CHECKLIST.md
          ├── create_new_file *.py (all files)
          ├── run_terminal_command "python main.py"
          ├── fix errors, re-run until clean
          └── create_new_file BUILD_REPORT.md
```

---

## Components

### Tool Registry (`assistant/tool_registry.py`)

The entry point for all `!task` commands. Introduced to fix a critical bug where `self.tools` was never defined, causing every coding command to silently fall through to the LLM chat.

```python
from assistant.tool_registry import registry

# How brain_pipeline.py calls it:
handled, resp = registry.execute(user_text, self, server_id)
```

The `coding-agent` handler is registered at priority 10 with these triggers:

```python
["!task", "build me", "create a", "make a", "write a",
 "make me a", "build a", "code a", "create me"]
```

**Adding a new tool without touching brain_pipeline.py:**

```python
# Option A: add a block in tool_registry.py
@registry.tool(triggers=["!deploy", "deploy to"])
def deploy_handler(text, brain, server_id):
    # your logic
    return True, "Deployed!"

# Option B: drop a file at tools/deploy_tool.py
# registry.load_all(tools_dir) auto-discovers *_tool.py files
```

---

### Coding Agent (`tools/coding_agent.py`)

**Location:** `/mnt/storage/pi-assistant/tools/coding_agent.py`
**Runs on:** Raspberry Pi 5

Orchestrates the entire pipeline from Discord to VS Code.

**Key responsibilities:**
- Parses the task description and detects project type from keywords
- Calls `skill_injector.find_skills_for_task()` with Discord interaction callbacks
- Optionally loads `uncodixfy.md` UI rules and appends them to SPEC
- Calls `task_router.route_task()` for planning (LM Studio or Ollama fallback)
- Builds a full `SPEC.md` with type contract + injected skills
- POSTs to `/copilot/task` on the VS Code Bridge

**Reply inbox (for skill selection):**

```python
# http_server.py calls this when a Discord reply arrives during skill selection:
coding_agent.deliver_reply(server_id, "1,3")
# → unblocks the waiting build thread
# → continues with user-selected skills
```

**Supported project types:**

| Type | Trigger keywords |
|------|-----------------|
| `pygame_game` | game, roguelike, platformer, shooter, arcade, dungeon, scroller |
| `web_app` | web, website, flask, fastapi, django, html, api, server |
| `cli_tool` | cli, command, script, tool, utility, terminal |
| `discord_bot` | discord, bot, slash command |
| `data_science` | data, analysis, pandas, csv, plot, chart, ml, pytorch, scikit, polars, dask |
| `general_python` | (fallback) |

**SPEC.md contract for pygame games:**
- Python 3.10+, Pygame 2.x
- All visuals via pygame primitives only (no image files)
- Game loop with `dt = clock.tick(60) / 1000.0`
- ZERO pass statements, ZERO TODOs, ZERO placeholder functions
- `import sys` at top of `main.py`

---

### Skill Injector (`tools/skill_injector.py`)

**Location:** `/mnt/storage/pi-assistant/tools/skill_injector.py`
**Runs on:** Raspberry Pi 5

Scores the entire skill library against the project type and either auto-injects the top results or prompts the user via Discord when many candidates are found.

**Skill roots scanned:**

```python
SKILLS_ROOT = Path("/mnt/storage/pi-assistant/skills/antigravity-awesome-skills/skills")

_SKILLS_EXTRA = [
    Path("/mnt/storage/pi-assistant/skills/claude-skills"),
    Path("/mnt/storage/pi-assistant/skills/claude-scientific-skills/scientific-skills"),
    Path("/mnt/storage/pi-assistant/skills/superpowers/skills"),
    Path("/mnt/storage/pi-assistant/skills/ui_ux_pro_max_skill/skills"),
    Path("/mnt/storage/pi-assistant/skills/custom"),
]
```

**Interactive selection flow:**

```
INTERACTIVE_THRESHOLD = 5   # candidates needed to trigger Discord prompt
INTERACTION_TIMEOUT   = 60  # seconds before auto-fallback
```

1. If ≥5 candidates: call `notify_fn` with numbered list → block on `wait_fn`
2. Reply `"1,3"` → use skills 1 and 3
3. Reply `"all"` → use all candidates
4. Reply Enter or `"auto"` → use top-N automatically
5. Timeout (60s) → auto-select top-3, continue build

**Two public functions:**

```python
# Used by coding_agent — scores + interactive selection
find_skills_for_task(task_text, project_type, notify_fn=None, wait_fn=None)
→ list[str]  # skill content strings to inject into SPEC

# Used for early Discord preview (no interaction)
get_skill_summary(task_text, project_type)
→ str  # "📘 Skills: pygame-2d-games, game-development"
```

**Keyword scoring (avoid false positives):**

```python
# ✅ Use specific folder names, not generic words
"pygame_game": ["pygame", "2d-games", "game-development", "platformer", "arcade"]
# ❌ Avoid: "game", "animation" — matches three.js/anime.js skills in pygame builds
```

---

### VS Code Bridge (`server.js`)

**Location:** `G:\Jeeves\vscode-bridge\server.js`
**Runs on:** Windows PC
**Port:** 5055
**Version:** v4.4

Exposes the PC filesystem and shell to the Pi over LAN.

**Key behavior of `/copilot/task`:**
1. Creates the project folder under `G:\Jeeves\projects\`
2. Writes `SPEC.md`
3. Opens VS Code with `code --new-window "<project_path>"`
4. Writes `.continue\autoprompt.md` — the full autonomous build prompt
5. Writes `pending_prompt.txt` **immediately** (full autoPrompt)
6. Re-writes `pending_prompt.txt` after 8s **only if already consumed** — catches the new window once it finishes loading

---

### VS Code Extension (`extension.js`)

**Location:** `C:\Users\<you>\.vscode\extensions\jeeves-copilot-bridge\`
**Version:** v2.2

> ⚠️ VS Code loads extensions from `C:\Users\<you>\.vscode\extensions\jeeves-copilot-bridge\`, **not** from `G:\Jeeves\vscode-bridge\`. Always copy both files to the extensions folder after updating.

**Primary path — `autoprompt.md`:**
- Polls `{workspace}\.continue\autoprompt.md` every 1 second
- When found: reads content, deletes file (consume-once), sends to Continue

**Startup scan (v2.2 — key fix):**
- On activation, scans for both `autoprompt.md` and `pending_prompt.txt` for 30 seconds
- Catches files written before the new VS Code window finished loading
- Without this, fresh windows race-condition out and Continue never fires

**Fallback path — `pending_prompt.txt`:**
- Polls `G:\Jeeves\vscode-bridge\pending_prompt.txt` every 1 second
- Re-written by `server.js` after 8s if already consumed (new-window safety net)

**Busy guard:** Auto-expires after 10 minutes — prevents permanent lock if a build hangs.

**Sending to Continue (3 retries, 3s apart):**
1. Waits up to 30s for Continue extension to be active
2. Writes prompt to VS Code clipboard
3. Opens new Continue session (`continue.focusContinueInputWithNewSession`)
4. Focuses Continue input box
5. Pastes from clipboard (`editor.action.clipboardPasteAction`)
6. Submits (`continue.acceptInput`)

---

### Continue Config (`config.yaml`)

**Location:** `C:\Users\Jerry\.continue\config.yaml`

```yaml
name: Jeeves
version: 1.0.0
models:
  - name: Qwen 14B Coder (PC)
    provider: lmstudio
    model: qwen2.5-coder-14b-instruct
    apiBase: http://localhost:1234/v1

  - name: Gemma3 4B (Pi)
    provider: ollama
    model: gemma3:4b
    apiBase: http://192.168.1.170:11434

tabAutocompleteModel:
  name: Qwen 3B Autocomplete (PC)
  provider: lmstudio
  model: qwen2.5-coder-3b-instruct
  apiBase: http://localhost:1234/v1
```

---

## End-to-End Flow

```
1. Discord: "jeeves !task build a mega man game"

2. Pi (brain_pipeline.py → tool_registry):
   - tool_registry.execute() → matched: coding-agent (priority 10)
   - coding_agent.handle_task_tool() called

3. Pi (skill_injector):
   - Detects: pygame_game
   - Scores 978+ skills → finds 6 candidates
   - Sends Discord menu: "1. pygame-2d-games  2. game-development..."
   - Waits up to 60s for reply → user sends "1,2"
   - Injects selected SKILL.md content into SPEC.md

4. Pi (task_router):
   - Probes PC :1234 → LM Studio online
   - Plans with Qwen 14B Coder (~27ms/token)

5. Pi (coding_agent → bridge):
   - Builds SPEC.md (plan + skills + Uncodixfy rules)
   - POST /copilot/task → bridge
   - Streams progress to Discord via /notify

6. PC (server.js v4.4):
   - Creates: G:\Jeeves\projects\mega_man_game\
   - Writes:  SPEC.md
   - Writes:  .continue\autoprompt.md
   - Runs:    code --new-window "G:\Jeeves\projects\mega_man_game"
   - Writes:  pending_prompt.txt IMMEDIATELY
   - After 8s: re-writes pending_prompt.txt IF consumed (new-window safety net)

7. PC (VS Code + extension.js v2.2):
   - Startup scan catches files written before window loaded
   - Detects autoprompt.md OR pending_prompt.txt
   - Waits up to 30s for Continue to be active (3 retries, 3s apart)
   - Opens new Continue session, pastes prompt, submits

8. PC (Continue + Qwen 14B via LM Studio):
   - read_file SPEC.md
   - create_new_file CHECKLIST.md
   - create_new_file main.py, player.py, enemy.py...
   - run_terminal_command "python main.py"
   - fix errors, re-run until zero errors
   - create_new_file BUILD_REPORT.md

9. Discord: "🏁 Jeeves done — Continue is building autonomously in VS Code"
```

---

## Local LLM Setup

| Model | Where | Purpose | Speed |
|-------|-------|---------|-------|
| `qwen2.5:0.5b` | Pi / Ollama | Fast planning fallback | ~20s |
| `qwen2.5:1.5b` | Pi / Ollama | Chat & reasoning fallback | ~30s |
| `qwen2.5-coder-14b-instruct` | PC / LM Studio | All code generation | ~27ms/token |
| `qwen2.5-coder-3b-instruct` | PC / LM Studio | Inline autocomplete | fast |

**LM Studio settings:**
- Port: `1234`
- Model: `qwen2.5-coder-14b-instruct-q4_k_m.gguf`
- GPU: RTX 4070 (49/49 layers offloaded)
- Context: 32768 tokens
- Parallel slots: 4
- Serve on Local Network: enabled

---

## Bridge Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------| 
| GET | `/ping` | Health check, returns version |
| GET | `/health` | Simple ok response |
| POST | `/open` | Open path in VS Code |
| POST | `/read` | Read file contents |
| GET | `/read?path=` | Read file (mcp_client compat) |
| POST | `/write` | Write file to PC filesystem |
| POST | `/ls` | List directory |
| GET | `/list?path=` | Recursive file list |
| POST | `/run` | Run command; `async:true` launches PS1 build loop |
| **POST** | **`/copilot/task`** | **Main endpoint — full pipeline trigger** |
| POST | `/copilot/chat` | Queue message for Continue via pending_chat.txt |
| POST | `/copilot/patch` | Write file patch |

**`/copilot/task` body:**
```json
{
  "task": "build a mega man game",
  "project_path": "G:\\Jeeves\\projects\\mega_man_game",
  "spec": "# Task\n...",
  "skip_copilot": false,
  "async": false
}
```

---

## File Reference

### Pi Side

```
/mnt/storage/pi-assistant/
├── assistant/
│   ├── tool_registry.py     ← priority dispatch (NEW)
│   ├── brain_pipeline.py    ← calls tool_registry first
│   ├── http_server.py       ← /ask delivers skill replies (v2.1.2)
│   └── task_router.py       ← model router (LM Studio / Ollama)
└── tools/
    ├── coding_agent.py      ← main orchestrator + reply inbox
    └── skill_injector.py    ← skill scoring + interactive selection
```

### PC Side

```
G:\Jeeves\
├── vscode-bridge\
│   ├── server.js             ← HTTP bridge (v4.4)
│   ├── start-bridge.ps1      ← bridge launcher
│   ├── pending_prompt.txt    ← trigger file (written by server.js)
│   └── pending_chat.txt      ← direct chat trigger
│
└── projects\
    └── <project_name>\
        ├── SPEC.md            ← written by Pi before VS Code opens
        ├── .continue\
        │   └── autoprompt.md ← autonomous build prompt (consumed once)
        ├── CHECKLIST.md       ← written by Continue
        ├── BUILD_REPORT.md    ← written by Continue when done
        └── main.py (etc.)

C:\Users\Jerry\.continue\
└── config.yaml               ← Continue model + autocomplete config

C:\Users\Jerry\.vscode\extensions\jeeves-copilot-bridge\
├── extension.js              ← Jeeves agent watcher (v2.2)
└── package.json              ← extension manifest
```

---

## Configuration

### Pi (`coding_agent.py`)

```python
VSCODE_HOST = "http://192.168.1.153:5055"   # PC bridge address
DAEMON_URL  = "http://127.0.0.1:8001/notify" # Pi notify endpoint
PC_DEFAULT  = "G:\\Jeeves\\projects"          # where projects are created
```

### PC Bridge (`server.js`)

```javascript
const PROJECTS_ROOT = "G:\\Jeeves\\projects";
const PI_URL        = "http://192.168.1.170:8001";
const PORT          = 5055;
```

---

## Adding a New Project Type

In `coding_agent.py`, add keywords to `_PROJECT_KEYWORDS` and a contract to `_CONTRACTS`:

```python
_PROJECT_KEYWORDS = {
    "my_new_type": ["keyword1", "keyword2"],
    ...
}

_CONTRACTS = {
    "my_new_type": (
        "## Implementation Contract\n\n"
        "- Your rules here\n"
    ),
    ...
}
```

In `skill_injector.py`, add the matching keyword list for skill scoring:

```python
_TASK_KEYWORDS = {
    "my_new_type": ["keyword1", "keyword2", "related-skill-folder-name"],
    ...
}
```

---

## Troubleshooting

### `[TOOLS] Matched: 'coding-agent'` but `name 'Path' is not defined`

`from pathlib import Path` is missing from `coding_agent.py`. Ensure line 26 reads:
```python
from pathlib import Path
```

### Continue doesn't fire — Output channel is empty

Extension installed at wrong location. Copy to the extensions folder and reload:

```powershell
$ext = "C:\Users\Jerry\.vscode\extensions\jeeves-copilot-bridge"
Copy-Item "G:\Jeeves\vscode-bridge\extension.js" "$ext\extension.js" -Force
Copy-Item "G:\Jeeves\vscode-bridge\package.json"  "$ext\package.json"  -Force
```

Then `Ctrl+Shift+P` → `Developer: Reload Window`. Confirm:
```
[Extension Host] [Jeeves] Jeeves Agent v2.2 activating...
```

### Skill selection menu appears but reply is ignored

`http_server.py` must check `_try_deliver_reply()` **before** calling `get_brain()`. Verify v2.1.2 is deployed:
```bash
grep "v2.1.2\|deliver_reply" /mnt/storage/pi-assistant/assistant/http_server.py
```

### `!task` falls through to LLM chat instead of building

`tool_registry.py` not deployed or `brain_pipeline.py` not updated. Verify:
```bash
python3 -c "from assistant.tool_registry import registry; print(registry.list_tools())"
```
Should show `coding-agent` and `tools-list`.

### SPEC validation failed / architecture looped

`qwen2.5:0.5b` looped in architecture planning. Handled automatically — `coding_agent.py` uses pre-filled templates for `pygame_game` so the model only fills in Enemy subclass descriptions. Build proceeds regardless.

### Planning takes > 30s

LM Studio not running or PC is off. The build falls back to Pi's `qwen2.5:1.5b`. Check:
```bash
curl http://192.168.1.153:1234/v1/models  # from Pi
```

### Files created with SyntaxError on line 1 (markdown fence bug)

Continue wrote ` ```python ` as the first line of a `.py` file. Fixed in `server.js` v4.4 — the autoPrompt includes explicit "CRITICAL FILE CREATION RULES" with wrong/right examples requiring raw Python, never markdown fences.
