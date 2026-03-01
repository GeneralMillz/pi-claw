# 🤵 Jeeves

**A fully self-hosted AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Orchestrates GitHub Copilot to build software on your behalf.

![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)
![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)
![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)
![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)
![License](https://img.shields.io/badge/License-MIT-green)

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant that runs on a **Raspberry Pi 5**. It connects to your Discord servers and gives you a personal AI that:

- 💬 **Chats** with persistent per-server memory and conversation history
- 📅 **Manages your calendar** (Google Calendar)
- 📧 **Reads and sends email** (IMAP/SMTP)
- 🎨 **Generates UI/UX design systems** with AI
- 🖥️ **Controls VS Code on your PC** over LAN — read, write, run files
- 🤖 **Orchestrates GitHub Copilot** — Jeeves plans, Copilot builds
- 📡 **Streams live updates to Discord threads** during long-running tasks
- 🔍 **Indexes your codebase** — find any file, class, or function by name
- 📺 **Controls Chromecast** (volume, pause, play)
- 🧠 **Per-server persistent memory** — remembers your context, projects, and preferences
- 📋 **Audit logs** every tool call
- 🔧 **Background job queue** — supervisor runs indexing and maintenance tasks without blocking

All AI runs **locally on your Pi**. No OpenAI API costs. No cloud dependency.

> **You can rename it.** "Jeeves" is just the default activation word and persona. Change it to anything you like in the server config.

---

## Architecture

```
Discord (multiple servers)
       │
       ▼
pi-discord-bot.service         ← asyncio Discord client
       │  POST /ask
       ▼
pi-assistant.service           ← HTTP daemon :8001
       │
       ├── Tool layer           ← assistant_tools.py
       │     ├── !task    ──────────────────────────────────┐
       │     ├── !index / !findfile / !findsymbol            │
       │     ├── !email                                      │
       │     ├── !calendar                                   ▼
       │     ├── !design      VS Code Bridge (your PC :5055)
       │     ├── !cast        /open /read /write /ls /run
       │     └── !vscode ──→  /copilot/task → SPEC.md → Copilot agent
       │
       ├── Brain pipeline      ← Qwen 1.5b (always warm)
       │     ├── Per-server memory (markdown files)
       │     ├── Fact injection
       │     └── Ollama /v1/chat/completions
       │
       └── Supervisor          ← background orchestration loop
             ├── Job queue     (index_project, etc.)
             └── Coding tasks  (Architect → Coder → QA)

Streaming:
  coding_agent → POST /notify → queue
  Discord bot polls GET /notify every 2s
  → creates thread on "Task started" message
  → streams all updates into thread
  → thread auto-archives when task completes

Project Index:
  !index → job queue → supervisor walks directory
  → AST symbol extraction → SQLite
  → !findfile / !findsymbol query instantly
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Board | Raspberry Pi 4 (4GB) | **Raspberry Pi 5 (8GB)** |
| Storage | 32GB SD card | **NVMe SSD (128GB+)** |
| OS | Raspberry Pi OS Bookworm 64-bit | **Debian Trixie 64-bit** |
| Network | WiFi | **Ethernet** |

---

## Quick Start

```bash
git clone https://github.com/GeneralMillz/pi-claw.git
cd pi-claw
chmod +x install.sh
./install.sh
```

Then follow the post-install steps printed by the installer.

Full guide: **[docs/INSTALL.md](docs/INSTALL.md)**

---

## Commands

| Command | Description |
|---------|-------------|
| `!task <description>` | Plan + hand off to Copilot (streams to thread) |
| `!task <desc> --path G:\myproject` | Specify output directory |
| `!index [path]` | Index a project directory (default: pi-assistant) |
| `!findfile <pattern>` | Search indexed files by path fragment |
| `!findsymbol <name>` | Search indexed Python classes/functions |
| `!email unread` | Check unread email |
| `!email send \| to \| subject \| body` | Send email |
| `!addevent \| title \| YYYY-MM-DD \| HH:MM` | Add calendar event |
| `!getevents \| start \| end` | Get calendar events |
| `!design <project description>` | Generate UI/UX design system |
| `!cast volume 50` | Set Chromecast volume |
| `!cast pause / play / stop` | Chromecast playback control |
| `!vscode ping` | Check VS Code bridge |
| `!vscode ls <path>` | List directory on PC |
| `!vscode read <path>` | Read file from PC |
| `!vscode write <path> <content>` | Write file to PC |
| `!vscode run <cmd>` | Run shell command on PC |
| `!audit` | Show last 20 tool call logs |
| `!latency` | Measure model response time |
| `!modelinfo` | Show AI model config |
| `!help` | Full command list |

Natural language also works for calendar, design, cast, and task triggers.

---

## AI Models

| Model | Size | Purpose |
|-------|------|---------|
| `qwen2.5:1.5b` | 1.1GB | Core chat (always warm) |
| `gemma3:4b` | 3.3GB | Task planning / reasoning |
| `qwen2.5-coder:7b` | 4.7GB | Code generation |
| `gemma2:2b` | 1.6GB | Summarization / QA |

All run locally via [Ollama](https://ollama.ai). No API keys required.

---

## How !task Works

1. You say `jeeves !task build a snake game in pygame`
2. Jeeves detects the project type (`pygame_game`, `web_app`, `cli_tool`, etc.)
3. Posts "Task started" in `#jeeves` and **creates a thread** on that message
4. Plans with `gemma3:4b` — all heartbeats stream into the thread every 15s
5. Builds a structured `SPEC.md` with file layout, classes, dependencies, pseudocode
6. Sends SPEC.md to your PC via VS Code bridge
7. VS Code extension reads SPEC.md and pastes it directly into Copilot Chat
8. Copilot implements the full project
9. Thread auto-archives

---

## Documentation

| Doc | Contents |
|-----|---------|
| [docs/INSTALL.md](docs/INSTALL.md) | Full step-by-step installation guide |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Server config, memory, personas, models |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [docs/COPILOT.md](docs/COPILOT.md) | VS Code + GitHub Copilot orchestration setup |

---

## Renaming Jeeves

Change the activation word in your server config:

```json
{
  "activation_word": "atlas",
  "persona_file": "config/personas/atlas.txt"
}
```

Create `config/personas/atlas.txt` with your custom persona. Done.

---

## License

MIT — see [LICENSE](LICENSE)
