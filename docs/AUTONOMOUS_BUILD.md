# Jeeves Autonomous Build System

> **Full documentation for the Continue + LM Studio autonomous development pipeline.**
> Covers the VS Code Bridge, Continue agent integration, local LLM setup, and how every component connects.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
  - [Coding Agent — Pi (`coding_agent.py`)](#coding-agent-coding_agentpy)
  - [VS Code Bridge — PC (`server.js`)](#vs-code-bridge-serverjs)
  - [VS Code Extension (`extension.js`)](#vs-code-extension-extensionjs)
  - [Continue Config (`config.json`)](#continue-config-configjson)
- [End-to-End Flow](#end-to-end-flow)
- [Local LLM Setup](#local-llm-setup)
- [Bridge Endpoints](#bridge-endpoints)
- [File Reference](#file-reference)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Overview

When you send `!task build a mega man game` in Discord, Jeeves orchestrates an autonomous build pipeline that:

1. Plans the project using a fast local model on the Pi
2. Writes a full `SPEC.md` to the PC via the VS Code Bridge
3. Opens VS Code to the project folder (forced fresh window)
4. Injects an autonomous build prompt into Continue
5. Continue + Qwen 14B builds the entire project — creating files, running code, fixing errors — without any human input

This is a self-hosted replacement for GitHub Copilot Workspace, running entirely on your local network.

---

## Architecture

```
Discord (!task)
    │
    ▼
Pi5 — coding_agent.py
    │  • Detects project type
    │  • Plans with qwen2.5:0.5b (Ollama, ~20s)
    │  • Builds SPEC.md
    │
    ▼  POST /copilot/task
PC — server.js (VS Code Bridge, port 5055)
    │  • Creates project folder
    │  • Writes SPEC.md
    │  • Opens VS Code (--new-window)
    │  • Writes .continue/autoprompt.md into project
    │  • Writes pending_prompt.txt (fallback, 5s delay)
    │
    ▼  (file system event)
PC — extension.js (Jeeves VS Code Extension)
    │  • Polls workspace for .continue/autoprompt.md
    │  • Detects file, writes prompt to clipboard
    │  • Opens new Continue session
    │  • Pastes and submits prompt to Continue
    │
    ▼
PC — Continue (VS Code, Agent mode)
    │  • Model: qwen2.5-coder-14b-instruct (LM Studio)
    │  • Tools: read_file, create_new_file, edit_existing_file,
    │           run_terminal_command, ls, grep_search
    │  • Reads SPEC.md
    │  • Creates CHECKLIST.md
    │  • Implements all files
    │  • Runs python main.py
    │  • Fixes errors and re-runs until zero errors
    │  • Writes BUILD_REPORT.md
    │
    ▼
Finished project running on PC
```

---

## Components

### Coding Agent (`coding_agent.py`)

**Location:** `/mnt/storage/pi-assistant/tools/coding_agent.py`  
**Runs on:** Raspberry Pi 5

Orchestrates the entire pipeline from Discord to VS Code. Triggered by `!task <description>` in Discord.

**Key responsibilities:**
- Parses the `!task` command and extracts the project description
- Detects project type from keywords (pygame_game, web_app, cli_tool, discord_bot, etc.)
- Calls `qwen2.5:0.5b` via Ollama for fast planning (~20s)
- Builds a detailed `SPEC.md` with type-specific implementation contracts
- POSTs to `/copilot/task` on the VS Code Bridge — single call that kicks off everything

**Supported project types:**

| Type | Trigger keywords |
|------|-----------------|
| `pygame_game` | game, roguelike, roguelite, platformer, shooter, zelda, mario, arcade, dungeon, scroller |
| `web_app` | web, website, flask, fastapi, django, html, api, server |
| `cli_tool` | cli, command, script, tool, utility, terminal |
| `discord_bot` | discord, bot, slash command |
| `data_science` | data, analysis, pandas, csv, plot, chart, ml |
| `general_python` | (fallback) |

**SPEC.md contract for pygame games:**
- Python 3.10+, Pygame 2.x
- All visuals via pygame primitives only (no image files)
- Game loop with `dt = clock.tick(60) / 1000.0`
- ZERO pass statements, ZERO TODOs, ZERO placeholder functions
- `import sys` at top of `main.py`

---

### VS Code Bridge (`server.js`)

**Location:** `G:\Jeeves\vscode-bridge\server.js`  
**Runs on:** Windows PC  
**Port:** 5055  
**Start:** `start-bridge.ps1`  
**Current version:** v4.4

Exposes the PC filesystem and shell to the Pi over LAN. The Pi treats the PC as a remote agent.

**Key behavior of `/copilot/task`:**
1. Creates the project folder under `G:\Jeeves\projects\`
2. Writes `SPEC.md`
3. Opens VS Code with `code --new-window "<project_path>"`
4. Writes `.continue/autoprompt.md` into the project — the full autonomous build prompt
5. Writes `pending_prompt.txt` **immediately** (full autoPrompt, not just task text) — any already-open VS Code window picks it up within 1s
6. Re-writes `pending_prompt.txt` after 8s **only if it was already consumed** — catches the new window once it finishes loading

---

### VS Code Extension (`extension.js`)

**Location:** `C:\Users\<you>\.vscode\extensions\jeeves-copilot-bridge\`  
**Runs on:** Windows PC, inside VS Code  
**Current version:** v2.2

> ⚠️ **Install path:** VS Code loads the extension from `C:\Users\<you>\.vscode\extensions\jeeves-copilot-bridge\`, **not** from `G:\Jeeves\vscode-bridge\`. Always copy both files to the extensions folder after updating.

Bridges the file system trigger to Continue's chat input. Runs inside VS Code as an extension, polling the workspace for signals from the bridge.

**Primary path — `autoprompt.md`:**
- Polls `{workspace}/.continue/autoprompt.md` every 1 second
- When found: reads content, deletes file (consume-once), sends to Continue

**Startup scan (v2.2 — key fix):**
- On activation, scans for both `autoprompt.md` and `pending_prompt.txt` for 30 seconds
- Catches files written before the new VS Code window finished loading
- Without this, the race condition causes Continue to never fire on fresh windows

**Fallback path — `pending_prompt.txt`:**
- Polls `G:\Jeeves\vscode-bridge\pending_prompt.txt` every 1 second
- Contains the **full autoPrompt** (written immediately by `server.js` — no 5s delay)
- Re-written by `server.js` after 8s if already consumed, as a new-window safety net

**Busy guard (v2.2):**
- Auto-expires after 10 minutes — prevents permanent lock if a build hangs

**Sending to Continue (3 retries, 3s apart):**
1. Waits up to 30s for Continue extension to be active
2. Writes prompt to VS Code clipboard
3. Opens new Continue session (`continue.focusContinueInputWithNewSession`)
4. Focuses Continue input box
5. Pastes from clipboard (`editor.action.clipboardPasteAction`)
6. Submits (`continue.acceptInput`)

---

### Continue Config (`config.json`)

**Location:** `C:\Users\Jerry\.continue\config.json`

Configures Continue to use LM Studio as the model provider with an autonomous developer system prompt baked in.

```json
{
  "models": [{
    "title": "Qwen 14B Coder (PC)",
    "provider": "lmstudio",
    "model": "qwen2.5-coder-14b-instruct",
    "apiBase": "http://192.168.1.153:1234/v1",
    "contextLength": 8192,
    "systemMessage": "You are an autonomous senior developer..."
  }]
}
```

**Custom slash commands:**
- `/implement` — full autonomous build from SPEC.md
- `/fix` — fix all errors and run until clean
- `/audit` — audit project, fix gaps, write BUILD_REPORT.md

---

## End-to-End Flow

```
1. Discord: "jeeves !task build a mega man game"

2. Pi (coding_agent.py):
   - Detects: pygame_game
   - Plans with qwen2.5:0.5b (pre-filled architecture template — prevents looping)
   - Injects relevant skills from library (e.g. game-development, 2d-games)
   - Builds SPEC.md (includes implementation contract + injected skills)
   - POST /copilot/task → bridge

3. PC (server.js v4.4):
   - Creates: G:\Jeeves\projects\mega_man_game\
   - Writes:  SPEC.md
   - Writes:  .continue\autoprompt.md  (the full task prompt)
   - Runs:    code --new-window "G:\Jeeves\projects\mega_man_game"
   - Writes:  pending_prompt.txt IMMEDIATELY (full prompt, not just task)
   - After 8s: re-writes pending_prompt.txt IF already consumed (new-window fallback)

4. PC (VS Code + extension.js v2.2):
   - Startup scan fires on activation — catches files written before window loaded
   - Detects autoprompt.md OR pending_prompt.txt (whichever arrives first)
   - Waits up to 30s for Continue extension to be active
   - Writes prompt to clipboard, opens new Continue session, pastes, submits
   - Retries up to 3 times if Continue isn't ready yet

5. PC (Continue + Qwen 14B via LM Studio):
   - read_file SPEC.md
   - ls (see existing files)
   - create_new_file CHECKLIST.md
   - create_new_file main.py, player.py, enemy.py, etc.  (raw Python — no markdown fences)
   - edit_existing_file (implement everything)
   - run_terminal_command "python main.py"
   - (fix errors, run again)
   - run_terminal_command "python main.py"  ← zero errors
   - create_new_file BUILD_REPORT.md

6. Discord: "Jeeves done — Continue is building autonomously in VS Code"
```

---

## Local LLM Setup

| Model | Where | Purpose | Speed |
|-------|-------|---------|-------|
| `qwen2.5:0.5b` | Pi / Ollama | Planning & summarization | ~20s |
| `qwen2.5:1.5b` | Pi / Ollama | Chat & reasoning | ~30s |
| `qwen2.5-coder-14b-instruct` | PC / LM Studio | All code generation | ~27ms/token |

**LM Studio settings:**
- Port: `1234`
- Model file: `qwen2.5-coder-14b-instruct-q4_k_m.gguf`
- GPU: RTX 4070 (49/49 layers offloaded)
- Context: 8192 tokens
- Parallel slots: 4

**LM Studio must be running** before any `!task` command. Continue and the bridge both point to `http://192.168.1.153:1234/v1`.

---

## Bridge Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/ping` | Health check, returns version |
| GET | `/health` | Simple ok response |
| POST | `/open` | Open path in VS Code |
| POST | `/read` | Read file contents |
| GET | `/read?path=` | Read file (mcp_client.py compat) |
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
├── tools/
│   └── coding_agent.py      ← main orchestrator
├── assistant/
│   └── task_router.py       ← model router (Ollama)
└── discord_modular.py       ← Discord bot entry point
```

### PC Side

```
G:\Jeeves\
├── vscode-bridge\
│   ├── server.js             ← HTTP bridge (v4.4)
│   ├── start-bridge.ps1      ← bridge launcher
│   ├── jeeves_build.ps1      ← Aider build loop (fallback/legacy)
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
        └── main.py (etc.)     ← written by Continue

C:\Users\Jerry\.continue\
└── config.json               ← Continue model + system prompt config

C:\Users\Jerry\.vscode\extensions\jeeves-copilot-bridge\
├── extension.js              ← Jeeves agent watcher (v2.2)
└── package.json              ← extension manifest
```

> **Important:** VS Code loads extensions from `C:\Users\<you>\.vscode\extensions\`, not from `G:\Jeeves\vscode-bridge\`. After updating either file, copy both to the extensions folder and do `Ctrl+Shift+P` → `Developer: Reload Window`.

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

### Continue (`config.json`)

```json
"apiBase": "http://192.168.1.153:1234/v1"   // LM Studio on PC
"model":   "qwen2.5-coder-14b-instruct"
"contextLength": 8192
```

---

## Troubleshooting

### Continue doesn't fire — Output channel is empty

VS Code loaded the extension from the extensions folder, not from `G:\Jeeves\vscode-bridge\`. Always update both locations:

```powershell
$ext = "C:\Users\Jerry\.vscode\extensions\jeeves-copilot-bridge"
Copy-Item "G:\Jeeves\vscode-bridge\extension.js" "$ext\extension.js" -Force
Copy-Item "G:\Jeeves\vscode-bridge\package.json"  "$ext\package.json"  -Force
```

Then `Ctrl+Shift+P` → `Developer: Reload Window`. Confirm by checking the console (`Ctrl+Shift+P` → `Developer: Toggle Developer Tools`) for:
```
[Extension Host] [Jeeves] Jeeves Agent v2.2 activating...
```

### VS Code opens a blank window instead of the project folder

The `--folder-uri` flag is unreliable on Windows. The bridge uses `code --new-window "<path>"` (plain path). If this still fails, check that `code` is in your PATH:

```powershell
node -e "require('child_process').exec('code --version', (e,o) => console.log(o))"
```

### Continue input box is empty after VS Code opens

`autoprompt.md` was written but the extension didn't fire. Check:

1. **Output panel** → select `Jeeves Agent` to see extension logs
2. Confirm version shows `v2.2` in the Developer Console
3. Try `Ctrl+Shift+P` → `Developer: Reload Window` and run `!task` again
4. Check `G:\Jeeves\vscode-bridge\pending_prompt.txt` — if it exists and isn't being consumed, the extension isn't running

### "Last Session" shows in Continue (old context loaded)

The new session command failed. The extension tries `continue.focusContinueInputWithNewSession` then falls back. Check the Jeeves Agent output channel for which command succeeded.

### Bridge log shows `SPEC.md →` but no `OPEN` line

The `code` command failed silently. Run this in PowerShell to test:

```powershell
code --new-window "G:\Jeeves\projects\test_folder"
```

### SPEC validation failed: architecture looped

The `qwen2.5:0.5b` model repeated the directory block during architecture planning. This is handled automatically — `coding_agent.py` uses a pre-filled template for `pygame_game` projects so the model only needs to fill in Enemy subclass descriptions. On the second attempt, a valid SPEC is passed to Continue regardless. Check telemetry in Discord — `SPEC valid: False` is a warning only; the build still proceeds.

### Planning takes too long (>30s)

The planner uses `qwen2.5:0.5b`. If it's slow, check Ollama is running on the Pi:

```bash
ollama list
curl http://localhost:11434/api/tags
```

### Bridge version mismatch in logs

The startup log shows `v4.3` but header says `v4.4` — the old file is still loaded. Verify `start-bridge.ps1` is pointing to the correct `server.js`:

```powershell
# Should show v4.4 on both lines:
Select-String -Path "G:\Jeeves\vscode-bridge\server.js" -Pattern "v4\."
```

### Files created with SyntaxError on line 1 (markdown fence bug)

Continue wrote ` ```python ` as the first line of a `.py` file. This is fixed in `server.js` v4.4 — the `autoPrompt` now includes an explicit "CRITICAL FILE CREATION RULES" section with a wrong/right example showing that files must start with raw Python, never markdown fences.

### Adding a new project type

In `coding_agent.py`, add keywords to `_PROJECT_KEYWORDS` and an implementation contract to `_CONTRACTS`:

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
