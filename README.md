<div align="center">

# 🤵 Jeeves

**A fully self-hosted AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Orchestrates GitHub Copilot to build software on your behalf.

![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)
![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)
![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)
![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)
![License](https://img.shields.io/badge/License-MIT-green)

</div>

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant that runs on a **Raspberry Pi 5**. It connects to your Discord servers and gives you a personal AI that:

- 💬 **Chats** with persistent per-server memory and conversation history
- 📅 **Manages your calendar** (Google Calendar)
- 📧 **Reads and sends email** (IMAP/SMTP)
- 🎨 **Generates UI/UX design systems** with AI + Gemma summarization
- 🖥️ **Controls VS Code on your PC** over LAN — read, write, run files
- 🤖 **Orchestrates GitHub Copilot** — Jeeves plans, Copilot builds
- 📡 **Streams live updates to Discord** during long-running tasks
- 📺 **Controls Chromecast** (volume, mute)
- 🧠 **Per-server persistent memory** — Jeeves remembers your context, projects, and preferences
- 📋 **Audit logs** every tool call
- ☀️ **Morning briefing** — daily digest of calendar + email + system stats

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
       │     ├── !task    ─────────────────────────────────┐
       │     ├── !email                                     │
       │     ├── !calendar                                  ▼
       │     ├── !design      VS Code Bridge (your PC :5055)
       │     ├── !cast        /open /read /write /ls /run
       │     └── !vscode ──→  /copilot/task → SPEC.md → Copilot agent
       │
       └── Brain pipeline      ← Qwen 1.5b (always warm)
             ├── Per-server memory (markdown files)
             ├── Fact injection
             └── Ollama /v1/chat/completions

Streaming:
  coding_agent → POST /notify → queue → Discord bot polls GET /notify → channel.send()
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Board | Raspberry Pi 4 (4GB) | **Raspberry Pi 5 (8GB)** |
| Storage | 32GB SD card | **NVMe SSD (128GB+)** |
| OS | Raspberry Pi OS Bookworm 64-bit | **Ubuntu 24 64-bit** |
| Network | WiFi | **Ethernet** |

---

## Quick Start

```bash
git clone https://github.com/yourusername/jeeves.git
cd jeeves
chmod +x install.sh
./install.sh
```

Then follow the post-install steps printed by the installer.

Full guide: **[docs/INSTALL.md](docs/INSTALL.md)**

---

## Commands

| Command | Description |
|---------|-------------|
| `!task <description>` | Plan task + hand off to Copilot |
| `!task <desc> --path /your/path` | Specify output directory |
| `!email unread` | Check unread email |
| `!email send \| to \| subject \| body` | Send email |
| `!addevent \| title \| YYYY-MM-DD \| HH:MM` | Add calendar event |
| `!getevents \| start \| end` | Get calendar events |
| `!design <project description>` | Generate UI/UX design system |
| `!cast volume 50` | Set Chromecast volume |
| `!cast mute / unmute` | Mute Chromecast |
| `!vscode ping` | Check VS Code bridge |
| `!vscode ls <path>` | List directory on PC |
| `!vscode read <path>` | Read file from PC |
| `!vscode write <path> <content>` | Write file to PC |
| `!vscode run <cmd>` | Run shell command on PC |
| `!audit` | Show last 20 tool call logs |
| `!latency` | Measure model response time |
| `!modelinfo` | Show AI model config |
| `!help` | Full command list |

Natural language also works for calendar, design, cast, and task triggers — just talk to it.

---

## AI Models

| Model | Size | Purpose |
|-------|------|---------|
| `qwen2.5:1.5b` | 1.1GB | Core chat + planning (always warm) |
| `gemma2:2b` | 1.6GB | Design output summarization |
| `qwen2.5-coder:3b` | 1.9GB | Code generation (on-demand) |

All run locally via [Ollama](https://ollama.ai). No API keys or subscriptions required.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/INSTALL.md](docs/INSTALL.md) | Full step-by-step installation guide |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Server config, memory, personas, models |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [docs/COPILOT.md](docs/COPILOT.md) | VS Code + GitHub Copilot orchestration setup |

---

## Renaming Jeeves

Don't want a butler? Change the activation word in your server config:

```json
{
  "activation_word": "atlas",
  "persona_file": "atlas.txt"
}
```

Create `config/personas/atlas.txt` with your custom persona. Done.

---

## License

MIT — see [LICENSE](LICENSE)
