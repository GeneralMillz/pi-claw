# Copilot Orchestration

This document covers how Jeeves plans tasks and hands them off to GitHub Copilot in VS Code.

---

## How It Works

```
Discord: jeeves !task build a tetris clone in pygame
  ↓
Pi: detect project type → pygame_game
  ↓
Pi: plan with gemma3:4b (structured SPEC.md)
  ↓
Pi: POST /copilot/task to VS Code bridge server on PC
  ↓
PC: bridge writes SPEC.md to project folder
PC: bridge writes pending_prompt.txt
  ↓
VS Code extension: detects pending_prompt.txt
VS Code extension: reads SPEC.md content
VS Code extension: waits 6s for workspace to index
VS Code extension: pastes full SPEC.md into Copilot Chat
  ↓
Copilot: implements full project
```

---

## PC Bridge Setup

The bridge is a Node.js server that runs on your PC and accepts commands from the Pi over your LAN.

### Install

```powershell
mkdir G:\Jeeves\vscode-bridge
cd G:\Jeeves\vscode-bridge
npm init -y
npm install express
```

Copy `server.js` to `G:\Jeeves\vscode-bridge\server.js`

### Run

```powershell
node G:\Jeeves\vscode-bridge\server.js
```

Keep this running whenever you want Jeeves to be able to write to your PC. You can add it to Windows Task Scheduler or run it in a terminal you leave open.

The Pi connects to your PC at `http://192.168.1.XXX:5055` — update `VSCODE_HOST` in `coding_agent.py` to match your PC's local IP.

---

## VS Code Extension Setup

The extension watches for `pending_prompt.txt` and auto-fires Copilot Chat.

### Install

```powershell
# Create the extension directory
$ext = "$env:USERPROFILE\.vscode\extensions\jeeves-copilot-bridge"
New-Item -ItemType Directory -Force -Path $ext

# Copy files
Copy-Item "G:\Jeeves\vscode-bridge\extension.js" "$ext\extension.js" -Force
Copy-Item "G:\Jeeves\vscode-bridge\package.json"  "$ext\package.json"  -Force
```

### Extension package.json

```json
{
  "name": "jeeves-copilot-bridge",
  "displayName": "Jeeves Copilot Bridge",
  "version": "1.0.0",
  "engines": { "vscode": "^1.80.0" },
  "activationEvents": ["onStartupFinished"],
  "main": "./extension.js",
  "contributes": {
    "commands": [
      { "command": "jeeves.triggerCopilot", "title": "Jeeves: Trigger Copilot" },
      { "command": "jeeves.startWatcher",   "title": "Jeeves: Start Watcher" },
      { "command": "jeeves.stopWatcher",    "title": "Jeeves: Stop Watcher" }
    ]
  },
  "configuration": {
    "properties": {
      "jeeves.promptFile": {
        "type": "string",
        "default": "G:\\Jeeves\\vscode-bridge\\pending_prompt.txt"
      },
      "jeeves.pollIntervalMs": {
        "type": "number",
        "default": 1000
      },
      "jeeves.autoStart": {
        "type": "boolean",
        "default": true
      }
    }
  }
}
```

### Reload VS Code

`Ctrl+Shift+P` → `Developer: Reload Window`

Check it's running: `View → Output → Jeeves Copilot Bridge`

You should see:
```
[Jeeves] Copilot Bridge activating...
[Jeeves] Watching: G:\Jeeves\vscode-bridge\pending_prompt.txt
```

---

## What the Extension Does

When a task completes on the Pi:

1. Bridge writes `SPEC.md` to the project folder on your PC
2. Bridge writes `pending_prompt.txt` (trigger file)
3. Bridge calls `/project` to open the folder in VS Code

The extension:
1. Detects `pending_prompt.txt` (polls every 1 second)
2. Deletes the trigger file
3. Reads `SPEC.md` from the workspace root
4. Waits 6 seconds for VS Code to finish indexing the workspace
5. Pastes the full SPEC.md content directly into Copilot Chat
6. Submits with agent mode

**Why direct paste instead of `@workspace implement SPEC.md`?**  
`@workspace` requires Copilot to index the workspace before it can answer. On a freshly-opened folder this fails with "I can't answer that question with what I currently know about your workspace." Pasting the content directly bypasses this entirely.

---

## SPEC.md Format

The SPEC.md Jeeves generates is structured for Copilot to implement without any additional context:

```markdown
# Project Specification

## Task
build a tetris clone in pygame

## Project Type
`pygame_game`

## Architecture & Plan
### Project Overview
...
### File Structure
- main.py — entry point, initializes game and runs main loop
- game.py — Game class, game loop, state management
- tetromino.py — Tetromino class, shapes, rotation
...
### Classes & Key Components
...
### Dependencies
- pygame
...
### Implementation Order
1. Setup project structure
2. Implement Tetromino class
...
### Game Loop / Main Flow (pseudocode)
...

## Implementation Requirements
- Use Pygame. Target Python 3.10+.
- Use colored rectangles as placeholder sprites.
- Game must be runnable with `python main.py`.
- No placeholder comments like # TODO implement this.
- No stub functions that just pass.
- Make it actually run without errors on first try.
```

---

## Project Output Paths

By default, projects are written to `G:\Jeeves\projects\<slug>` on your PC.

Override with `--path`:
```
jeeves !task build a flask API --path G:\MyProjects\my-api
```

---

## Supported Project Types

Jeeves auto-detects the project type and tailors the plan and SPEC accordingly:

| Type | Keywords | Plan Focus |
|------|---------|-----------|
| `pygame_game` | pygame, game, rpg, platformer, tetris, snake | game states, sprites, collision, game loop |
| `web_app` | flask, fastapi, django, web app, api, crud | routes, DB schema, auth, folder structure |
| `cli_tool` | cli, terminal, script, argparse, automation | subcommands, validation, error handling |
| `discord_bot` | discord bot, slash command, cog | commands, events, intents |
| `data_science` | pandas, numpy, data, analysis, visualization | data pipeline, cleaning, output format |
| `general_python` | (everything else) | module layout, entry point, dependencies |

---

## Troubleshooting

**"I can't answer that question with what I currently know about your workspace"**  
The extension is still using the old version. Verify the new extension.js is deployed:
```powershell
cat "$env:USERPROFILE\.vscode\extensions\jeeves-copilot-bridge\extension.js" | Select-String "getSpecPath"
```
Should return a match. If not, re-copy extension.js and reload VS Code.

**Bridge offline (SPEC.md written locally instead of PC)**  
```powershell
# Check bridge is running on PC
curl http://localhost:5055/ping
# Should return: {"status":"ok"}
```

**Copilot Chat doesn't open**  
The `workbench.action.chat.open` command requires GitHub Copilot Chat extension to be installed and active. Install it from the VS Code marketplace.

**VS Code opens wrong folder**  
The project path is determined by the `--path` flag or auto-generated from the task description slug. Check the "Project:" line in the Discord thread for the actual path.
