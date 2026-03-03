# 🤵 Jeeves

**A fully self-hosted AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Builds software with GitHub Copilot. Now powers Claude Code — locally, for free.

![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)
![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)
![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)
![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)
![Claude Code](https://img.shields.io/badge/Claude_Code-Local_Backend-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant that runs on a **Raspberry Pi 5**. It connects to Discord, controls your PC over LAN, orchestrates GitHub Copilot to build full software projects — and now acts as the **local LLM backend for Claude Code**, replacing Anthropic's API entirely.

- 💬 **Chats** with persistent per-server memory and conversation history
- 📅 **Manages your calendar** (Google Calendar)
- 📧 **Reads and sends email** (IMAP/SMTP)
- 🎨 **Generates UI/UX design systems** with AI
- 🖥️ **Controls VS Code on your PC** over LAN — read, write, run files
- 🤖 **Orchestrates GitHub Copilot** — Jeeves plans, Copilot builds
- 📡 **Streams live updates to Discord threads** during long-running tasks
- 🔍 **Indexes your codebase** — find any file, class, or function instantly
- 📺 **Controls Chromecast** (volume, pause, play)
- 🧠 **Per-server persistent memory** — remembers context, projects, preferences
- 🆓 **Powers Claude Code locally** — zero Anthropic API costs

All AI runs **locally on your Pi**. No OpenAI. No Anthropic. No cloud dependency.

> **Rename it.** "Jeeves" is just the default activation word and persona. Change it to anything in the server config.

---

## Claude Code Integration *(New)*

Jeeves exposes an **OpenAI + Anthropic-compatible API** on port `8002`, letting you use Claude Code as a full IDE assistant powered entirely by your Pi.

```
Claude Code (Windows)
    ↓  POST /v1/messages
Jeeves openai_server.py (:8002)
    ↓  strips system prompts, extracts conversation
qwen2.5:1.5b via Ollama (Pi)
    ↓  response in ~5s
Claude Code displays answer
```

**Setup (Windows — one time):**
```powershell
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://192.168.1.170:8002", "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-api03-aaaa...aaaa-aaaaaaaa", "User")
# New PowerShell window:
cd G:\Jeeves && claude
```

Full details: [docs/CLAUDE_CODE_INTEGRATION.md](docs/CLAUDE_CODE_INTEGRATION.md)

---

## Architecture

```
Discord (multiple servers)
       │
       ▼
pi-discord-bot.service              ← asyncio Discord client
       │  POST /ask
       ▼
pi-assistant.service (:8001)        ← HTTP daemon
       │
       ├── Tool layer                ← assistant_tools.py (all failures silent)
       │     ├── !task  ─────────────────────────────────────┐
       │     ├── !index / !findfile / !findsymbol             │
       │     ├── !email                                       │
       │     ├── !calendar                                    ▼
       │     ├── !design           VS Code Bridge (PC :5055)
       │     ├── !cast             /open /read /write /run
       │     └── !vscode ───────→  /copilot/task → SPEC.md → Copilot agent
       │
       ├── Brain pipeline            ← qwen2.5:1.5b (always warm)
       │     ├── Per-server memory (markdown files)
       │     ├── Fact injection
       │     └── Ollama /v1/chat/completions
       │
       ├── Supervisor                ← background orchestration
       │     ├── Job queue (index_project, etc.)
       │     └── Coding tasks (Architect → Coder → QA)
       │
       └── openai_server.py (:8002)  ← Claude Code backend
             ├── POST /v1/messages   (Anthropic format)
             ├── POST /v1/chat/completions (OpenAI format)
             └── Strips Claude Code system prompts → passes clean USER turns to brain

Streaming:
  coding_agent → POST /notify → queue
  Discord bot polls GET /notify every 2s
  → creates thread on "Task started"
  → streams all updates into thread
  → thread auto-archives on completion
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

Full guide: [docs/INSTALL.md](docs/INSTALL.md)

---

## Commands

| Command | Description |
|---------|-------------|
| `!task <description>` | Plan + hand off to Copilot (streams to thread) |
| `!task <desc> --path G:\myproject` | Specify output directory |
| `!index [path]` | Index a project directory |
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
| `!vscode read / write / run / ls` | File and shell ops on PC |
| `!copilot <message>` | Start autonomous Copilot session |
| `!skill install` | Index and activate skill library (968+ skills) |
| `!skill search <query>` | Search available skills |
| `!audit` | Show last 20 tool call logs |
| `!latency` | Measure model response time |
| `!modelinfo` | Show AI model config |
| `!help` | Full command list |

Natural language also works for calendar, design, cast, and task triggers.

---

## AI Models

| Model | Size | Purpose |
|-------|------|---------|
| `qwen2.5:1.5b` | 1.1GB | Core chat — always warm, Claude Code backend |
| `gemma3:4b` | 3.3GB | Task planning / reasoning |
| `qwen2.5-coder:7b` | 4.7GB | Code generation |
| `gemma2:2b` | 1.6GB | Summarization / QA |
| `deepseek-r1:1.5b` | 1.1GB | Chain-of-thought reasoning |

All run locally via [Ollama](https://ollama.ai). No API keys required.

---

## How `!task` Works

1. You say `jeeves !task build a snake game in pygame`
2. Jeeves detects project type (`pygame_game`, `web_app`, `cli_tool`, etc.)
3. Posts "Task started" in `#jeeves` and **creates a Discord thread**
4. Plans with `gemma3:4b` — heartbeats stream into the thread every 15s
5. Builds a structured `SPEC.md` with file layout, classes, dependencies, pseudocode
6. Sends `SPEC.md` to your PC via VS Code bridge
7. VS Code extension reads `SPEC.md` and pastes it into Copilot Chat
8. Copilot implements the full project
9. Thread auto-archives

---

## Skill System

Jeeves includes a modular skill system with **968+ community skills** plus your own custom skills:

```bash
jeeves !skill install     # index and activate all skills
jeeves !skill search docker
jeeves !skill load docker-compose-generator
```

Skills are declarative `SKILL.md` files. Jeeves auto-injects relevant skills into the system prompt based on your query — giving domain-specific accuracy without manual configuration.

Full details: [docs/SKILLS.md](docs/SKILLS.md)

---

## Documentation

| Doc | Contents |
|-----|---------|
| [docs/INSTALL.md](docs/INSTALL.md) | Full step-by-step installation |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Server config, memory, personas, models |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [docs/COPILOT.md](docs/COPILOT.md) | VS Code + GitHub Copilot orchestration |
| [docs/CLAUDE_CODE_INTEGRATION.md](docs/CLAUDE_CODE_INTEGRATION.md) | Claude Code local backend setup |
| [docs/SKILLS.md](docs/SKILLS.md) | Skill system architecture and authoring guide |

---

## Renaming Jeeves

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
