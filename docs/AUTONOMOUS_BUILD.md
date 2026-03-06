# Jeeves Autonomous Build System

> **Full documentation for the Aider-powered autonomous development pipeline.**
> This covers the VS Code Bridge, the 8-phase build loop, local LLM integration, and how every component connects.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
  - [VS Code Bridge (`server.js`)](#vs-code-bridge-serverjs)
  - [The Build Loop (`jeeves_build.ps1`)](#the-build-loop-jeeves_buildps1)
  - [Coding Agent (`coding_agent.py`)](#coding-agent-coding_agentpy)
  - [Task Router (`task_router.py`)](#task-router-task_routerpy)
- [The 8-Phase Build Loop](#the-8-phase-build-loop)
- [Local LLM Setup](#local-llm-setup)
- [End-to-End Flow](#end-to-end-flow)
- [File Reference](#file-reference)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Overview

When you send `!task create a pokemon game` in Discord, Jeeves doesn't just ask an AI to write some code and hope for the best. It runs a **structured 8-phase autonomous development loop** that:

1. Plans with a fast local model on the Pi
2. Writes a detailed `SPEC.md` to your PC
3. Opens VS Code in the project folder
4. Launches a full autonomous build session using [Aider](https://aider.chat) + Qwen 14B
5. Audits, implements, tests, and polishes the project across 8 phases
6. Launches the finished product automatically

No cloud APIs. No subscriptions. No limits. Everything runs on your own hardware.

---

## Architecture

```
Discord
    |
    | !task <description>
    v
Pi (Raspberry Pi 5)
    |
    |-- coding_agent.py
    |     |-- Detects project type (game / web / cli / bot / data)
    |     |-- Builds short plan prompt
    |     |-- Calls task_router.py → qwen2.5:0.5b (Ollama, fast)
    |     |-- Builds SPEC.md from plan
    |     |-- POSTs to VS Code Bridge
    |
    | HTTP POST → 192.168.1.x:5055
    v
PC (Windows)
    |
    |-- server.js (VS Code Bridge, port 5055)
    |     |-- POST /write  → writes SPEC.md to project folder
    |     |-- POST /open   → opens VS Code in project folder
    |     |-- POST /run (async) → copies jeeves_build.ps1, launches it
    |
    |-- jeeves_build.ps1 (new PowerShell window)
    |     |-- Phase 1: Architecture Audit
    |     |-- Phase 2: Project Scaffold
    |     |-- Phase 3: Syntax Audit
    |     |-- Phase 4: Core Implementation
    |     |-- Phase 5: Features + Polish
    |     |-- Phase 6: Integration Test
    |     |-- Phase 7: Final Audit
    |     |-- Phase 8: Launch
    |
    |-- Aider (called by jeeves_build.ps1 at each phase)
    |     |-- Connects to LM Studio at http://localhost:1234/v1
    |     |-- Model: qwen2.5-coder-14b-instruct
    |     |-- Reads/writes files directly on disk
    |     |-- Git commits after every change
    |
    |-- LM Studio
          |-- Serves qwen2.5-coder-14b-instruct locally
          |-- OpenAI-compatible API at :1234
```

---

## Components

### VS Code Bridge (`server.js`)

A Node.js/Express HTTP server that runs on your PC and exposes file system and shell operations to the Pi over your local network.

**Location:** `G:\Jeeves\vscode-bridge\server.js`  
**Port:** `5055`  
**Start:** `node "G:\Jeeves\vscode-bridge\server.js"`

#### Endpoints

| Method | Path | Body | Description |
|--------|------|------|-------------|
| `GET` | `/ping` | — | Health check |
| `GET` | `/health` | — | Health check (alias) |
| `POST` | `/write` | `{ path, content }` | Write a file to the PC filesystem |
| `POST` | `/read` | `{ path }` | Read a file from the PC filesystem |
| `POST` | `/open` | `{ path }` | Open a folder in VS Code |
| `POST` | `/ls` | `{ path }` | List directory contents |
| `POST` | `/run` | `{ command, cwd, async }` | Run a shell command. If `async: true`, fires in a new visible PowerShell window without waiting |
| `POST` | `/copilot/task` | `{ task, project_path, spec, skip_copilot }` | Write SPEC.md and open VS Code (legacy endpoint, still works) |
| `POST` | `/copilot/chat` | `{ message, file }` | Queue a message for the Continue extension watcher |
| `POST` | `/copilot/patch` | `{ filePath, content }` | Write a file patch directly |

#### The `/run` async mode

When `async: true` is sent, the bridge uses `start powershell.exe` to open a **new visible PowerShell window** that runs the command. This is how the build loop is launched — the Pi fires the request and gets an immediate response, while the build runs independently on the PC.

```json
POST /run
{
  "command": "powershell -ExecutionPolicy Bypass -File jeeves_build.ps1",
  "cwd": "G:\\Jeeves\\projects\\my_game",
  "async": true
}
```

#### Starting the bridge

```powershell
# G:\Jeeves\vscode-bridge\start-bridge.ps1
node "G:\Jeeves\vscode-bridge\server.js"
```

The bridge must be running on your PC whenever you want `!task` to work. Keep the window open.

---

### The Build Loop (`jeeves_build.ps1`)

A PowerShell script that orchestrates the full 8-phase autonomous build. It is stored in `G:\Jeeves\vscode-bridge\` and automatically copied into each new project folder by `server.js` when a build is triggered.

**Location:** `G:\Jeeves\vscode-bridge\jeeves_build.ps1`  
**Copied to:** `G:\Jeeves\projects\<project_name>\jeeves_build.ps1`  
**Run by:** `server.js` via `/run` async

You can also run it manually at any time:

```powershell
cd G:\Jeeves\projects\my_project
powershell -ExecutionPolicy Bypass -File jeeves_build.ps1
```

#### How it calls Aider

Each phase calls Aider with a specific focused prompt:

```powershell
$AIDER_BASE = "aider --openai-api-base http://localhost:1234/v1 --openai-api-key dummy --model openai/qwen2.5-coder-14b-instruct --yes-always --no-suggest-shell-commands"

aider $AIDER_BASE --message "Your phase-specific prompt here" SPEC.md CHECKLIST.md
```

- `--yes-always` — never prompts for confirmation, fully autonomous
- `--no-suggest-shell-commands` — prevents Aider from suggesting commands instead of writing code
- Each phase passes only the files relevant to that phase

---

### Coding Agent (`coding_agent.py`)

The Pi-side orchestrator. Receives the task from Discord, plans it, builds the SPEC, and hands off to the bridge.

**Location:** `/mnt/storage/pi-assistant/tools/coding_agent.py`

#### Project type detection

The agent automatically detects what kind of project to build based on keywords:

| Type | Keywords |
|------|----------|
| `pygame_game` | game, platformer, roguelike, roguelite, mario, shooter, dungeon, arcade... |
| `web_app` | flask, fastapi, api, dashboard, website, crud... |
| `cli_tool` | cli, command line, script, utility, argparse... |
| `discord_bot` | discord bot, discord.py, slash command... |
| `data_science` | pandas, numpy, data, csv, analysis, ml... |
| `general_python` | everything else |

Each type gets a different implementation contract injected into SPEC.md with specific rules (e.g. pygame games must use primitives only, no image files).

#### Planning model

Planning uses `qwen2.5:0.5b` via Ollama — the smallest, fastest model. The prompt is kept intentionally short (under 50 words) so the Pi responds in under 30 seconds. The Pi only needs to produce a rough plan — Qwen 14B on the PC does the actual heavy thinking during the build phases.

#### What gets written to SPEC.md

```
# SPEC.md — Project Specification
## Request          ← exact user input
## Project Type     ← detected type
## Plan             ← Pi model's brief plan
## Implementation Contract  ← type-specific rules
## Rules            ← universal rules for Aider
```

---

### Task Router (`task_router.py`)

Routes inference requests to the right model. Pi models handle chat, planning, and summarization. Aider handles all code generation via LM Studio on the PC.

**Location:** `/mnt/storage/pi-assistant/assistant/task_router.py`

| Task Type | Model | Where |
|-----------|-------|-------|
| `core` | `qwen2.5:1.5b` | Pi (Ollama) |
| `reasoner` | `qwen2.5:1.5b` | Pi (Ollama) |
| `summarizer` | `qwen2.5:0.5b` | Pi (Ollama) |
| `coder` | `qwen2.5-coder:3b` | Pi (Ollama) |
| `vscode` | `qwen2.5-coder-14b-instruct` | PC (LM Studio via Aider) |

---

## The 8-Phase Build Loop

Every `!task` runs through all 8 phases sequentially. Each phase has a specific job and a specific Aider prompt. VS Code shows files appearing and updating in real time as each phase runs.

---

### Phase 1 — Architecture Audit

**Goal:** Produce a complete, exhaustive checklist before writing a single line of code.

Aider reads `SPEC.md` and outputs `CHECKLIST.md` — a markdown file with a checkbox for every file, class, method, and feature that must exist in the finished product. This becomes the project's source of truth for all subsequent phases.

**Output:** `CHECKLIST.md`

```
- [ ] main.py — entry point, game loop
- [ ] player.py — Player class with move(), shoot(), take_damage()
- [ ] enemy.py — BaseEnemy, FastEnemy, BossEnemy classes
- [ ] game_state.py — GameState dataclass, State enum
...
```

---

### Phase 2 — Project Scaffold

**Goal:** Create every file with correct imports and structure before any logic is written.

Aider creates all files listed in `SPEC.md` and `CHECKLIST.md` with proper imports, class definitions, and method stubs. The entire project structure exists on disk and is syntactically valid Python before implementation begins.

**Why this matters:** Starting with a complete scaffold means implementation errors are isolated — a bug in `enemy.py` can't prevent `player.py` from being importable.

**Output:** All project files created with stubs

---

### Phase 3 — Syntax Audit

**Goal:** Guarantee zero syntax errors before implementation begins.

The build script runs a Python syntax check on every `.py` file independently:

```powershell
python -c "import ast; ast.parse(open('file.py').read())"
```

Any files that fail are collected and passed back to Aider with a targeted fix prompt. The check runs again to confirm. Phase 4 does not begin until all files pass.

**Output:** All `.py` files confirmed syntax-clean

---

### Phase 4 — Core Implementation

**Goal:** Implement the skeleton — the minimum viable product.

Aider implements the core of the project: the main loop, primary data structures, and the most critical user interactions. The prompt explicitly forbids `pass` statements and `# TODO` comments for anything in the plan.

For a pygame game this means: working game loop, player movement, basic collision, state machine.  
For a web app: all routes returning real responses, database connected.  
For a CLI: all commands working end to end.

**Output:** A runnable (if incomplete) project

---

### Phase 5 — Features and Polish

**Goal:** Implement every remaining checkbox in `CHECKLIST.md`.

Aider works through every unchecked item: secondary features, edge case handling, error messages, sound, HUD elements, logging. The prompt requires checking off each item as it's implemented.

**Output:** Feature-complete project

---

### Phase 6 — Integration Test

**Goal:** Find the entry point and confirm it is runnable.

The build script searches for the entry point automatically:

```powershell
$candidates = @("main.py", "src/main.py", "app.py", "run.py", "bot.py", "game.py")
```

It syntax-checks the entry point and all its imports. If anything fails, Aider is called to fix it. If no entry point exists, Aider is asked to create `main.py`.

**Output:** Confirmed working entry point

---

### Phase 7 — Final Audit

**Goal:** Human-readable summary of everything that was built.

Aider does a final pass: checks every checkbox in `CHECKLIST.md`, identifies anything missing or broken, fixes it, and writes `BUILD_REPORT.md` — a plain-English summary of what was built, what works, and the exact command to run it.

**Output:** `BUILD_REPORT.md`, `CHECKLIST.md` fully checked

```markdown
# Build Report

## What was built
A 2D Pygame roguelite with procedural dungeon generation...

## Entry point
python main.py

## Known issues
None

## How to run
pip install pygame
python main.py
```

---

### Phase 8 — Launch

**Goal:** Run the project.

The build script displays `BUILD_REPORT.md` in the terminal, then executes the entry point. For a pygame game, the window opens. For a web app, the server starts. The PowerShell window stays open so you can see the output.

---

## Local LLM Setup

The build pipeline uses two models on two different machines.

### Pi (Ollama) — planning only

```bash
ollama pull qwen2.5:0.5b    # planning / summarization (fast)
ollama pull qwen2.5:1.5b    # chat / reasoning
ollama pull qwen2.5-coder:3b  # lightweight code tasks
```

### PC (LM Studio) — code generation

1. Download [LM Studio](https://lmstudio.ai)
2. Download `qwen2.5-coder-14b-instruct`
3. Start the local server: **Local Server tab → Start Server**
4. Confirm it's running at `http://localhost:1234/v1`

### Aider installation

```bash
pip install aider-chat
```

Verify connection to LM Studio:

```bash
aider --openai-api-base http://localhost:1234/v1 --openai-api-key dummy --model openai/qwen2.5-coder-14b-instruct
```

---

## End-to-End Flow

```
User: !task create a roguelite game

1. Discord → Pi (discord_bot.py receives message)

2. Pi: coding_agent.py
   - Detects type: pygame_game
   - Builds 50-word plan prompt
   - Calls qwen2.5:0.5b → plan in ~20s
   - Builds SPEC.md (project type + plan + contracts + rules)
   - POSTs SPEC.md → bridge /write
   - POSTs /open → VS Code opens project folder
   - POSTs /run async=true → jeeves_build.ps1 launches

3. PC: jeeves_build.ps1 opens in new PowerShell window
   - Phase 1: Aider → CHECKLIST.md
   - Phase 2: Aider → all files scaffolded
   - Phase 3: Python syntax check → fix any errors
   - Phase 4: Aider → core implementation
   - Phase 5: Aider → all features
   - Phase 6: Entry point check → fix if needed
   - Phase 7: Aider → BUILD_REPORT.md
   - Phase 8: python main.py → game launches

4. Discord: Jeeves notifies at each step
   ✅ Plan ready (18s, model=qwen2.5:0.5b)
   📄 SPEC.md written on PC
   🖥️ VS Code opened
   🚀 Aider launched on PC — Qwen 14B is building...
   🏁 Jeeves done.
```

---

## File Reference

### On the PC (`G:\Jeeves\vscode-bridge\`)

| File | Purpose |
|------|---------|
| `server.js` | VS Code Bridge HTTP server |
| `jeeves_build.ps1` | 8-phase autonomous build loop |
| `start-bridge.ps1` | Launcher script for the bridge |
| `node_modules/` | Express dependency |

### On the Pi (`/mnt/storage/pi-assistant/`)

| File | Purpose |
|------|---------|
| `tools/coding_agent.py` | Task orchestrator, SPEC builder, bridge caller |
| `assistant/task_router.py` | Routes inference to Pi models or PC/Aider |

### Generated per project (`G:\Jeeves\projects\<name>\`)

| File | Created by | Purpose |
|------|-----------|---------|
| `SPEC.md` | Pi bridge `/write` | Single source of truth for the build |
| `CHECKLIST.md` | Phase 1 (Aider) | Every feature as a checkbox |
| `BUILD_REPORT.md` | Phase 7 (Aider) | Summary of what was built |
| `jeeves_build.ps1` | Bridge `/run` (copied) | The build script itself |
| `*.py` | Phases 2-5 (Aider) | The actual project code |
| `.git/` | Aider (auto) | Git repo, every change committed |

---

## Configuration

### Pi — `coding_agent.py`

```python
VSCODE_HOST = "http://192.168.1.153:5055"   # your PC's local IP
PC_DEFAULT  = "G:\\Jeeves\\projects"         # where projects are created
```

### PC — `server.js`

```javascript
const PROJECTS_ROOT = "G:\\Jeeves\\projects";
const PORT = 5055;
```

### PC — `jeeves_build.ps1`

```powershell
$AIDER_BASE = "aider --openai-api-base http://localhost:1234/v1 --openai-api-key dummy --model openai/qwen2.5-coder-14b-instruct --yes-always --no-suggest-shell-commands"
```

---

## Troubleshooting

### Bridge not reachable from Pi

```
❌ Could not write SPEC.md to PC: HTTPConnectionPool(host='192.168.1.x', port=5055)
```

- Make sure `start-bridge.ps1` is running on the PC
- Confirm the IP in `coding_agent.py` matches your PC's actual local IP
- Check Windows Firewall isn't blocking port 5055

### Aider window opens but closes immediately

- Run `jeeves_build.ps1` manually from PowerShell to see the error
- Make sure `aider` is installed: `pip install aider-chat`
- Make sure LM Studio is running with a model loaded

### Planning takes more than 30 seconds

- The Pi is using a model that's too large for planning
- `task_router.py` should use `summarizer` task type for planning which maps to `qwen2.5:0.5b`
- Confirm Ollama is running: `ollama list`

### Build loop runs but produces broken code

- This is normal for complex projects — run `jeeves_build.ps1` again manually
- Aider + Qwen 14B will pick up where it left off, reading the existing files
- You can also run a single targeted pass: `aider --message "fix all errors in main.py" main.py`

### Git conflicts between phases

- Each Aider phase auto-commits its changes
- If phases conflict, run: `git log --oneline` to see all commits
- Undo a phase: `git revert HEAD`

---

## Adding New Project Types

To add a new project type (e.g. Unity, React, etc.), edit `coding_agent.py`:

1. Add keywords to `_PROJECT_TYPES`:
```python
"react_app": [
    "react", "nextjs", "typescript frontend", "vite",
],
```

2. Add a type hint to `_build_plan_prompt()`:
```python
"react_app": "React + TypeScript app. Vite for bundling. All components in src/components/.",
```

3. Add an implementation contract to `_build_spec_md()`:
```python
"react_app": (
    "## Implementation Contract\n\n"
    "- Entry point: npm run dev\n"
    "- TypeScript strict mode. No any types.\n"
    "- All components functional with hooks.\n"
),
```
