# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Jeeves** is an autonomous coding agent system that lets a Raspberry Pi assistant trigger end-to-end software project creation via GitHub Copilot Chat in VS Code. It uses a file-watcher IPC pattern and two AI tiers (local reasoning + code generation) to fully automate project scaffolding.

## Architecture

The system has three layers:

1. **`coding_agent.py`** (Python) — Orchestrates task execution: plans with `deepseek-r1`, generates code with `qwen-coder`, writes files via the bridge, runs/auto-fixes output, and streams Discord notifications.

2. **`vscode-bridge/server.js`** (Node.js/Express on port 5055) — HTTP bridge that exposes file I/O and shell execution endpoints. On `/copilot/task`, writes a `SPEC.md` and drops `pending_prompt.txt` to trigger the extension.

3. **`vscode-bridge/extension.js`** (VS Code Extension) — Polls `pending_prompt.txt` and `pending_chat.txt` every 1s, builds a Copilot prompt (using `SPEC.md` as source of truth), and auto-submits to Copilot Agent mode.

**Data flow:** Pi `!task` command → `coding_agent.py` → POST `/copilot/task` → `server.js` writes files → `extension.js` detects file → injects into Copilot Chat → project created in `projects/`.

## Key Configuration Constants

In `coding_agent.py`:
- `VSCODE_HOST = "http://192.168.1.153:5055"` — bridge address (PC on LAN)
- `DAEMON_URL = "http://127.0.0.1:8001/notify"` — Discord notification endpoint
- `PC_DEFAULT = "G:\\Jeeves\\projects"` — output directory on Windows
- `PI_DEFAULT = "/mnt/storage/projects"` — output directory on Pi

## Commands

**Start the bridge (Windows):**
```powershell
.\start-bridge.ps1
# Or manually:
cd vscode-bridge && npm install && node server.js
```

**Install VS Code extension:**
Copy `vscode-bridge/` to `%USERPROFILE%\.vscode\extensions\jeeves-copilot-bridge\`, then restart VS Code.

**Trigger a task (from Pi):**
```
!task create a basic platformer in pygame
!task build a flask API --path /custom/path
```

**Bridge API endpoints** (all on port 5055):
- `GET /ping` — health check
- `POST /write` — write file `{path, content}`
- `POST /read` — read file `{path}`
- `POST /run` — execute shell command `{command}` (30s timeout)
- `POST /ls` — list directory `{path}`
- `POST /open` — open path in VS Code
- `POST /copilot/task` — create SPEC.md + trigger Copilot flow
- `POST /copilot/chat` — send autonomous chat message

## Task Detection Keywords

`coding_agent.py` triggers the pipeline when a message contains: `!task`, `build me`, `create a`, `make a`, `write a`, `make me a`, `build a`, `code a`, `create me`.

## Project Output Structure

Generated projects land in `projects/<task-slug>/` and always include a `SPEC.md` used as the single source of truth for Copilot implementation. The agent auto-fixes runtime errors up to 3 times before reporting failure.

## Jeeves Local AI (Claude Code Integration)

Claude Code routes through **Jeeves** on a Raspberry Pi (`192.168.1.170`) instead of the Anthropic API.
All inference is handled by `qwen2.5:1.5b` via Ollama — no API costs.

See [`docs/CLAUDE_CODE_INTEGRATION.md`](docs/CLAUDE_CODE_INTEGRATION.md) for full setup details.

**Quick Start (Windows — first time only):**
```powershell
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://192.168.1.170:8002", "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaa", "User")
# Open a new PowerShell window, then:
cd G:\Jeeves && claude   # choose option 1 (Yes) when prompted
```

**Notes for local model:**
- Keep responses short — `qwen2.5:1.5b` has limited context
- Do not reference Claude-specific capabilities (artifacts, web search, etc.)
- Prefer direct answers over lengthy explanations
