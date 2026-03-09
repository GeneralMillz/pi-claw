# 🤵 Jeeves

**A fully self-hosted AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Orchestrates AI agents to build software on your behalf.

[![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)](https://www.raspberrypi.com)
[![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)](https://python.org)
[![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)](https://discord.com)
[![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)](https://ollama.ai)
[![LM Studio](https://img.shields.io/badge/LM_Studio-PC_Inference-purple)](https://lmstudio.ai)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant that runs on a **Raspberry Pi 5**. It connects to your Discord servers and gives you a personal AI that:

* 💬 **Chats** with persistent per-server memory and conversation history
* 📅 **Manages your calendar** (Google Calendar)
* 📧 **Reads and sends email** (IMAP/SMTP)
* 🎨 **Generates UI/UX design systems** with AI + Gemma summarization
* 🖥️ **Controls VS Code on your PC** over LAN — read, write, run files
* 🤖 **Orchestrates AI coding agents** — Jeeves plans, agents build
  - **Continue + LM Studio** (default, fully local, unlimited)
  - **GitHub Copilot** (alternative, requires subscription)
  - **cn CLI** (fully autonomous headless mode)
* 📡 **Streams live updates to Discord** during long-running tasks
* 📺 **Controls Chromecast** (volume, mute)
* 🧠 **Per-server persistent memory** — Jeeves remembers your context, projects, and preferences
* 📋 **Audit logs** every tool call
* ☀️ **Morning briefing** — daily digest of calendar + email + system stats

All AI runs **locally**. Pi handles chat + planning. PC handles heavy code generation via LM Studio. No OpenAI API costs. No cloud dependency.

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
       │     └── !vscode ──→  /copilot/task → SPEC.md
       │                            │
       │                            ├──► Continue extension (default)
       │                            │      └── Qwen 14B via LM Studio :1234
       │                            ├──► cn CLI (--cn flag, fully autonomous)
       │                            │      └── Qwen 14B via LM Studio :1234
       │                            └──► GitHub Copilot (--copilot flag)
       │
       └── Brain pipeline      ← Qwen 1.5b (always warm on Pi)
             ├── Per-server memory (markdown files)
             ├── Fact injection
             └── Ollama /v1/chat/completions

PC Model Routing (task_router.py):
  LM Studio online  →  Qwen 14B Coder (primary, best quality)
  LM Studio offline →  Pi Ollama fallback (always-on)

Streaming:
  coding_agent → POST /notify → queue → Discord bot polls GET /notify → channel.send()
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
| --- | --- | --- |
| Board | Raspberry Pi 4 (4GB) | **Raspberry Pi 5 (8GB)** |
| Storage | 32GB SD card | **NVMe SSD (128GB+)** |
| OS | Raspberry Pi OS Bookworm 64-bit | **Ubuntu 24 64-bit** |
| Network | WiFi | **Ethernet** |
| PC (optional) | Any Windows PC | **i9 + 32GB RAM + RTX 4070** |

> The PC is optional but recommended for heavy code generation. When your PC is on and LM Studio is running, Jeeves automatically routes coding tasks to the 14B model. When your PC is off, it falls back to Pi Ollama seamlessly.

---

## Quick Start

```bash
git clone https://github.com/GeneralMillz/pi-claw.git
cd pi-claw
chmod +x install.sh
./install.sh
```

Then follow the post-install steps printed by the installer.

Full guide: **[INSTALL.md](INSTALL.md)**

---

## Commands

| Command | Description |
| --- | --- |
| `!task <description>` | Plan + hand off to Continue (Qwen 14B) |
| `!task <desc> --cn` | Use cn CLI for fully autonomous headless build |
| `!task <desc> --both` | Trigger both Continue extension AND cn |
| `!task <desc> --path G:\myproject` | Specify custom output directory |
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

### Pi Models (always-on, via Ollama)

| Model | Size | Purpose |
| --- | --- | --- |
| `qwen2.5:1.5b` | 1.1GB | Core chat + planning (always warm) |
| `gemma2:2b` | 1.6GB | Design output summarization |
| `qwen2.5-coder:3b` | 1.9GB | Code generation fallback |

### PC Models (on-demand, via LM Studio)

| Model | Size | Purpose |
| --- | --- | --- |
| `Qwen2.5-Coder-14B-Instruct` Q4_K_M | 8.99GB | Primary coding agent (chat + agent mode) |
| `Qwen2.5-Coder-3B-Instruct` Q4_K_M | 2.1GB | Inline autocomplete in VS Code |

> PC models are loaded on-demand. LM Studio does not need to run all the time — only during coding sessions. When the PC is off, Jeeves falls back to Pi models automatically via `task_router.py`.

---

## Documentation

| Doc | Contents |
| --- | --- |
| [INSTALL.md](INSTALL.md) | Full step-by-step installation guide |
| [CONFIGURATION.md](CONFIGURATION.md) | Server config, memory, personas, models |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [CONTINUE.md](CONTINUE.md) | VS Code + Continue + LM Studio orchestration setup (default) |
| [COPILOT.md](COPILOT.md) | VS Code + GitHub Copilot orchestration setup (alternative) |

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
