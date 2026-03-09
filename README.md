# 🤵 Jeeves

**A fully self-hosted, distributed AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Orchestrates AI agents to build software on your behalf.  
**$0/month. No cloud. No API keys.**

[![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)](https://www.raspberrypi.com/products/raspberry-pi-5/)
[![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)](https://python.org)
[![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)](https://discord.com)
[![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)](https://ollama.ai)
[![LM Studio](https://img.shields.io/badge/LM_Studio-PC_Inference-purple)](https://lmstudio.ai)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant that runs across a **Raspberry Pi 5** (always-on brain) and a **Windows PC** (heavy compute). It connects to your Discord servers and gives you a personal AI that:

- 💬 **Chats** with persistent per-server memory and conversation history
- 🧠 **Routes tasks** intelligently — fast Pi models for chat, powerful PC models for code
- 🌐 **Scrapes the web** — content extraction, price monitoring, DuckDuckGo search
- 🖥️ **Controls VS Code / Cursor on your PC** over LAN — read, write, run files
- 🤖 **Orchestrates Continue + Cursor** — Jeeves plans via SPEC.md, agents build
- 🔧 **MCP Agent Mode** — natural language multi-tool orchestration via the PC's 14B model
- 📅 **Manages your calendar** (Google Calendar)
- 📧 **Reads and sends email** (IMAP/SMTP)
- 🎨 **Generates UI/UX design systems**
- 📺 **Controls Chromecast** (volume, mute)
- 📡 **Streams live updates to Discord** during long-running tasks
- 🗃️ **BrainDB** — SQLite-backed memory, tool audit log, task queue, project tracking
- ☀️ **Morning briefing** — daily digest of calendar + email + system stats

> **You can rename it.** "Jeeves" is the default activation word and persona. Change it to anything in the server config.

---

## Architecture

```
Discord (multiple servers)
         │
         ▼
pi-discord-bot.service          ← asyncio Discord client
         │  POST /ask
         ▼
pi-assistant.service            ← HTTP daemon :8001
         │
         ├── Tool layer          ← assistant_tools.py
         │     ├── !task  ──────────────────────────────────────┐
         │     ├── !scrape                                       │
         │     ├── !browse                                       ▼
         │     ├── !email         VS Code Bridge (PC :5055)
         │     ├── !calendar      /open /read /write /ls /run
         │     ├── !design        SPEC.md → Continue / Cursor
         │     └── !cast
         │
         ├── Brain pipeline      ← brain_pipeline.py
         │     ├── Model caps + generation params per model
         │     ├── keep_alive (model stays warm in Ollama)
         │     ├── Per-server memory (BrainDB + markdown)
         │     └── Ollama /v1/chat/completions
         │
         ├── Task router         ← task_router.py
         │     ├── Pi local:   qwen2.5:0.5b  (chat, default)
         │     ├── Pi local:   qwen2.5:1.5b  (reasoning)
         │     ├── Pi local:   qwen2.5-coder:3b (code)
         │     ├── PC agent:   Qwen2.5-Coder-14B via LM Studio
         │     └── MCP agent:  "jeeves agent: ..." → tool loop
         │
         └── BrainDB             ← brain_db.py (SQLite WAL)
               ├── Conversation history
               ├── Tasks, plans, subtasks
               ├── Agent runs + events
               ├── Tool audit log
               ├── Memory notes
               └── Project + file index

MCP Layer (mcp_registry.py + mcp_client.py):
  Tool catalogue → LM Studio 14B → tool calls → Pi executes → results → final answer → Discord

Streaming:
  coding_agent → POST /notify → queue → Discord bot polls GET /notify → channel.send()
```

---

## Two-Tier Intelligence

| Tier | Hardware | Models | Role |
|------|----------|--------|------|
| **Pi Brain** | Raspberry Pi 5 (8GB) | `qwen2.5:0.5b`, `qwen2.5:1.5b`, `qwen2.5-coder:3b` | Always-on, sub-second routing, chat, memory, planning |
| **PC Brain** | Windows PC (i9 / RTX 4070 / 32GB) | `Qwen2.5-Coder-14B` via LM Studio | Heavy inference, multi-file code, MCP agent orchestration |

The Pi handles everything instantly. The PC is only invoked for tasks that need serious reasoning or MCP agent mode.

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Board | Raspberry Pi 4 (4GB) | **Raspberry Pi 5 (8GB)** |
| Storage | 32GB SD card | **NVMe SSD (128GB+)** |
| OS | Raspberry Pi OS Bookworm 64-bit | **Ubuntu 24 64-bit** |
| Network | WiFi | **Ethernet** |
| PC (optional) | Any with Ollama | **i7+ / RTX GPU / 16GB+ RAM** |

---

## Quick Start

```bash
git clone https://github.com/GeneralMillz/pi-claw.git
cd pi-claw
chmod +x install.sh
./install.sh
```

Full guide: **[INSTALL.md](INSTALL.md)**

---

## Commands

### Core Chat
| Command | Description |
|---------|-------------|
| `jeeves <anything>` | Chat with the assistant |
| `jeeves agent: <request>` | MCP agent mode — multi-tool orchestration via PC 14B |
| `jeeves do: <request>` | Alias for agent mode |

### Web & Research
| Command | Description |
|---------|-------------|
| `!scrape <url>` | Extract main content from a URL |
| `!scrape price <url>` | Extract price from a product page |
| `!scrape search <query>` | DuckDuckGo search (ad-filtered) |
| `!scrape css=<selector> <url>` | CSS selector extraction |
| `!browse <url>` | Open URL in browser via Pinchtab |

### Coding & VS Code
| Command | Description |
|---------|-------------|
| `!task <description>` | Plan task → write SPEC.md → Continue/Cursor builds it |
| `!task <desc> --path /your/path` | Specify output directory |
| `!vscode ping` | Check VS Code bridge on PC |
| `!vscode ls <path>` | List directory on PC |
| `!vscode read <path>` | Read file from PC |
| `!vscode write <path> <content>` | Write file to PC |
| `!vscode run <cmd>` | Run shell command on PC |

### Calendar & Email
| Command | Description |
|---------|-------------|
| `!addevent \| title \| YYYY-MM-DD \| HH:MM` | Add calendar event |
| `!getevents \| start \| end` | Get calendar events |
| `!email unread` | Check unread email |
| `!email send \| to \| subject \| body` | Send email |

### System & Debug
| Command | Description |
|---------|-------------|
| `!latency` | Measure warm-path model response time |
| `!modelinfo` | Show current model + config |
| `!audit` | Show last 20 tool call logs |
| `!help` | Full command list |
| `!cast volume 50` | Set Chromecast volume |
| `!cast mute / unmute` | Mute/unmute Chromecast |

Natural language also works for calendar, email, scrape, and task triggers.

---

## AI Models

| Model | Size | Provider | Role |
|-------|------|----------|------|
| `qwen2.5:0.5b` | 394MB | Ollama (Pi) | Default chat — fast, snappy replies |
| `qwen2.5:1.5b` | 986MB | Ollama (Pi) | Reasoning, planning |
| `qwen2.5-coder:3b` | 1.9GB | Ollama (Pi) | Code generation (Pi-side) |
| `gemma3:4b` | 2.5GB | Ollama (Pi) | Design + summarization |
| `Qwen2.5-Coder-14B` | 9GB Q4 | LM Studio (PC) | Heavy code, MCP agent orchestration |

All models run **100% locally**. No OpenAI API. No subscriptions.

---

## MCP Agent Mode

Jeeves includes a full MCP (Model Context Protocol) layer for natural language multi-tool orchestration:

```
"jeeves agent: find the cheapest RTX 5090 and save it to memory"

  → PC 14B model receives tool catalogue
  → calls web_search("RTX 5090 cheapest price")
  → calls memory_save("RTX 5090: $1,999 at B&H as of March 2026")
  → returns final answer to Discord
```

All tool calls are logged to BrainDB's `tool_audit` table automatically.

See **[MCP.md](MCP.md)** for the full reference.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [INSTALL.md](INSTALL.md) | Full step-by-step installation guide |
| [CONFIGURATION.md](CONFIGURATION.md) | Server config, memory, personas, models |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [MCP.md](MCP.md) | MCP layer — registry, client, agent mode, tool catalogue |
| [COPILOT.md](COPILOT.md) | VS Code + Continue/Cursor orchestration setup |

---

## Renaming Jeeves

```json
{
  "activation_word": "atlas",
  "persona_file": "atlas.txt"
}
```

Create `config/personas/atlas.txt` with your custom persona. Done.

---

## Project Status

Actively used in production. Current focus:

- [x] Two-tier Pi + PC inference routing
- [x] BrainDB — full SQLite event store
- [x] Web scraping via Scrapling
- [x] MCP registry + client layer
- [x] MCP agent mode with PC 14B orchestration
- [x] Continue/Cursor SPEC.md pipeline
- [x] keep_alive warm model management
- [ ] MCP dashboard tool timeline UI
- [ ] Scheduled price monitoring via BrainDB jobs
- [ ] Voice input via Whisper

---

## License

MIT — see [LICENSE](LICENSE)
