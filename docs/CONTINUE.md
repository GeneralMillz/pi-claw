# Continue + LM Studio Orchestration

This document covers how Jeeves plans tasks and hands them off to **Continue** (VS Code extension) and **cn** (Continue CLI) using **LM Studio + Qwen 14B** running locally on your PC.

This is the **default agent** as of 2026. See [COPILOT.md](COPILOT.md) if you want to use GitHub Copilot instead.

---

## How It Works

```
Discord: jeeves !task build a tetris clone in pygame
  ↓
Pi: detect project type → pygame_game
  ↓
Pi: plan with local model via task_router.py
      → LM Studio online?  → Qwen 14B Coder (PC)
      → LM Studio offline? → qwen2.5:1.5b (Pi fallback)
  ↓
Pi: POST /copilot/task to VS Code bridge on PC
  ↓
PC: bridge writes SPEC.md to project folder
PC: bridge writes pending_prompt.txt
  ↓
VS Code extension: detects pending_prompt.txt
VS Code extension: reads SPEC.md content
VS Code extension: waits 6s for workspace to index
VS Code extension: pastes full SPEC.md into Continue chat
  ↓
Continue (Qwen 14B via LM Studio): implements full project
```

For `--cn` flag (fully autonomous):
```
  ↓ (instead of extension)
cn CLI: reads SPEC.md
cn CLI: creates all files, runs commands, fixes errors — no clicking required
```

---

## Discord Status Flow

When you run `!task`, Jeeves streams updates to Discord in real time:

```
⚙️ Task started — streaming updates incoming...
🔍 Type: `pygame_game`
⚙️ Agent: `Continue (Qwen 14B)` | Planning with local model...
⏳ Still planning... (15s)
⏳ Still planning... (30s)
✅ Plan ready (132123ms, model=qwen2.5-coder-14b-instruct)
📝 Writing SPEC.md for Continue...
✅ SPEC.md written on PC.
🚀 VS Code opening — Continue extension will trigger automatically.
🏁 Jeeves done — Continue (Qwen 14B) is building...
```

---

## PC Setup

### Step 1 — Install LM Studio

Download from [lmstudio.ai](https://lmstudio.ai) and install on your Windows PC.

### Step 2 — Download Models

In LM Studio search and download:

| Model | Quant | Size | Role |
|-------|-------|------|------|
| `Qwen/Qwen2.5-Coder-14B-Instruct-GGUF` | Q4_K_M | 8.99 GB | Chat / Agent |
| `Qwen/Qwen2.5-Coder-3B-Instruct-GGUF` | Q4_K_M | 2.1 GB | Autocomplete |

### Step 3 — Start LM Studio Server

1. Open LM Studio
2. Click the **Developer tab** (`<->` icon)
3. Click **Start Server**
4. Confirm: `HTTP server listening on port 1234`
5. Enable **"Serve on Local Network"** so the Pi can reach it

> Just-in-time model loading is on by default — models load automatically when requested.

### Step 4 — Install Node Bridge

```powershell
mkdir G:\Jeeves\vscode-bridge
cd G:\Jeeves\vscode-bridge
npm init -y
npm install express
```

Copy `server.js` to `G:\Jeeves\vscode-bridge\server.js`, then run:

```powershell
node G:\Jeeves\vscode-bridge\server.js
```

### Step 5 — Install VS Code Extension

```powershell
$ext = "C:\Users\$env:USERNAME\.vscode\extensions\jeeves-copilot-bridge"
New-Item -ItemType Directory -Force -Path $ext
Copy-Item "G:\Jeeves\vscode-bridge\extension.js" "$ext\extension.js" -Force
Copy-Item "G:\Jeeves\vscode-bridge\package.json"  "$ext\package.json"  -Force
```

> **Note:** VS Code always loads the extension from the `.vscode\extensions` folder. `G:\Jeeves\vscode-bridge\` is the source of truth — copy to extensions after every update.

#### Extension package.json (current)

```json
{
  "name": "jeeves-copilot-bridge",
  "displayName": "Jeeves Copilot Bridge",
  "version": "2.2.0",
  "engines": { "vscode": "^1.85.0" },
  "activationEvents": ["onStartupFinished"],
  "main": "./extension.js",
  "contributes": {
    "commands": [
      { "command": "jeeves.startWatcher", "title": "Jeeves: Start prompt watcher" },
      { "command": "jeeves.stopWatcher",  "title": "Jeeves: Stop prompt watcher" },
      { "command": "jeeves.triggerNow",   "title": "Jeeves: Trigger now (read SPEC.md)" }
    ],
    "configuration": {
      "title": "Jeeves Copilot Bridge",
      "properties": {
        "jeeves.promptFile":     { "type": "string",  "default": "G:\\Jeeves\\vscode-bridge\\pending_prompt.txt" },
        "jeeves.pollIntervalMs": { "type": "number",  "default": 1000 },
        "jeeves.autoStart":      { "type": "boolean", "default": true }
      }
    }
  }
}
```

Reload VS Code: `Ctrl+Shift+P` → `Developer: Reload Window`

Confirm it's running: `Ctrl+Shift+P` → `Developer: Toggle Developer Tools` → Console tab. Look for:
```
[Extension Host] [Jeeves] Jeeves Agent v2.2 activating...
[Extension Host] [Jeeves] Watching: G:\Jeeves\vscode-bridge\pending_prompt.txt
```

### Step 6 — Install Continue in VS Code

Extensions (`Ctrl+Shift+X`) → search **Continue** → install by `Continue.dev`

### Step 7 — Configure Continue

Edit `C:\Users\Jerry\.continue\config.yaml`:

```json
{
  "name": "Jeeves",
  "version": "1.0.0",
  "models": [
    {
      "name": "Qwen 14B Coder (PC)",
      "provider": "lmstudio",
      "model": "qwen2.5-coder-14b-instruct",
      "apiBase": "http://localhost:1234/v1"
    },
    {
      "name": "Gemma3 4B (Pi)",
      "provider": "ollama",
      "model": "gemma3:4b",
      "apiBase": "http://192.168.1.170:11434"
    }
  ],
  "tabAutocompleteModel": {
    "name": "Qwen 3B Autocomplete (PC)",
    "provider": "lmstudio",
    "model": "qwen2.5-coder-3b-instruct",
    "apiBase": "http://localhost:1234/v1"
  }
}
```

### Step 8 — Install cn CLI (for autonomous mode)

```powershell
npm i -g @continuedev/cli
```

---

## Pi Setup

Update `coding_agent.py` with your PC's local IP:

```python
VSCODE_HOST = "http://192.168.1.153:5055"   # your PC's LAN IP
CN_CONFIG   = r"C:\Users\Jerry\.continue\config.yaml"
CN_MODEL    = "Qwen 14B Coder (PC)"
```

Update `task_router.py` with your PC's LM Studio URL:

```python
LMSTUDIO_URL = "http://192.168.1.153:1234"  # or set LMSTUDIO_URL env var
```

---

## Ports & Endpoints

| Service | URL | Notes |
|---------|-----|-------|
| VS Code Bridge | `http://PC_IP:5055` | Node.js Express server |
| LM Studio API | `http://PC_IP:1234/v1` | OpenAI-compatible |
| LM Studio models | `http://PC_IP:1234/v1/models` | GET |
| Pi assistant | `http://127.0.0.1:8001` | HTTP daemon |
| Pi Ollama | `http://127.0.0.1:11434` | Fallback LLM |

---

## Task Flags

| Command | Agent | Mode |
|---------|-------|------|
| `!task <desc>` | Continue extension + Qwen 14B | Interactive, VS Code panel |
| `!task <desc> --cn` | cn CLI + Qwen 14B | Fully autonomous, no clicking |
| `!task <desc> --both` | Continue extension + cn | Both simultaneously |
| `!task <desc> --path G:\myproject` | (any) | Custom output path |

---

## cn CLI — Fully Autonomous Mode

`cn` is the Continue command-line agent. It reads your SPEC.md and implements the entire project without any human interaction — no clicking Apply, no clicking Run.

### Start manually

```powershell
cn --config "C:\Users\Jerry\.continue\config.yaml"
```

Confirm it shows:
```
Config: Jeeves
Model: Qwen 14B Coder (PC)
```

### Useful cn commands

| Command | What it does |
|---------|-------------|
| `cn --config "C:\Users\Jerry\.continue\config.yaml"` | Start with Jeeves config |
| `cn -p "your task"` | Headless mode, no interaction |
| `/model` | Switch models |
| `@filename.md` | Give context about a file |
| `!command` | Run a shell command directly |
| `cn --resume` | Resume previous session |
| `cn --allow Write()` | Auto-allow file writes |
| `cn --allow Bash()` | Auto-allow all shell commands |
| `Shift+Tab` at prompt | Allow current action + don't ask again |

### Fully autonomous one-liner

```powershell
cn --config "C:\Users\Jerry\.continue\config.yaml" --allow Write() --allow Bash() -p "read SPEC.md and build the entire project, run it when done and fix any errors"
```

---

## Model Routing (task_router.py)

Jeeves automatically picks the best available model at routing time:

```
!task received on Pi
  ↓
task_router.py probes http://PC_IP:1234/v1/models (2s timeout, cached 30s)
  ↓
PC online  →  Qwen 14B Coder via LM Studio  (best quality)
PC offline →  qwen2.5:1.5b via Pi Ollama    (always-on fallback)
```

No configuration needed — it just works. The probe result is cached for 30 seconds to avoid hammering the network.

---

## Using Continue in VS Code (Manual)

When your PC is on, you can also use Continue directly without going through Jeeves:

1. Start LM Studio server (port 1234)
2. Open project in VS Code
3. Click the **Continue icon** in the sidebar
4. Select **Qwen 14B Coder (PC)** from the model dropdown
5. Set mode to **Agent** (bottom left of chat panel)
6. Use `@filename` or `@workspace` to give context

When PC is off, switch to **Gemma3 4B (Pi)** in the model dropdown — it routes through your always-on Pi Ollama.

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

| Problem | Fix |
|---------|-----|
| `Cannot truncate prompt` in Continue | Increase context length in LM Studio model settings to 8192+ |
| `Unexpected endpoint` error | Make sure `apiBase` in config.yaml includes `/v1` |
| `Failed to load user assistants` in cn | Run `cn --config "C:\Users\Jerry\.continue\config.yaml"` explicitly |
| Model not responding | Check LM Studio server is started and showing green |
| cn asks permission every time | Press `Shift+Tab` or use `--allow` flags |
| Pi using slow model despite PC being on | LM Studio server not started — open LM Studio and start server |
| Pi fallback not working | Check Ollama is running: `ollama list` on Pi |
| Bridge offline | Run `curl http://localhost:5055/ping` on PC — should return `{"status":"ok"}` |

---

## PC Does Not Need to Run 24/7

Unlike the Pi (which runs as a systemd service), your PC only needs to be on during active coding sessions. The full flow when PC is off:

- Jeeves chat, memory, email, calendar → all work normally on Pi
- `!task` commands → plan and build using Pi's `qwen2.5:1.5b` (smaller but functional)
- Continue in VS Code → switch to **Gemma3 4B (Pi)** in the model dropdown

When you turn your PC on and start LM Studio, everything automatically upgrades to the 14B model.
