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
- 📱 **Builds Android apps** autonomously via Gemini API
- 🎨 **Generates UI/UX design systems**
- 📺 **Controls Chromecast** (volume, mute)
- 📡 **Streams live updates to Discord** during long-running tasks
- 🗃️ **BrainDB** — SQLite-backed memory, tool audit log, task queue, project tracking
- ☀️ **Morning briefing** — daily digest of calendar + email + system stats
- 📘 **978+ skills** — auto-injected into coding tasks based on project type

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
         ├── Tool Registry       ← tool_registry.py (NEW)
         │     ├── coding-agent  → !task, "build me", "create a", ...
         │     ├── tools-list    → !tools, !help tools
         │     └── (extensible via *_tool.py drop-ins)
         │
         ├── Tool layer          ← assistant_tools.py
         │     ├── !scrape
         │     ├── !browse
         │     ├── !email
         │     ├── !calendar
         │     ├── !android
         │     ├── !design
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

Skill System (skill_injector.py):
  978+ skills → keyword scoring → top-3 injected into every SPEC.md
  Interactive selection (≥5 candidates): Discord menu → user picks

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

Full guide: **[docs/INSTALL.md](docs/INSTALL.md)**

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
| `!browse <url>` | Navigate with headless Chromium via Pinchtab |
| `!browse snap <url>` | Interactive element snapshot with click refs |
| `!browse click <ref>` | Click element by ref |
| `!browse screenshot` | Capture viewport as Discord attachment |

### Coding & VS Code
| Command | Description |
|---------|-------------|
| `!task <description>` | Plan → SPEC.md → Continue/Cursor builds autonomously |
| `!task <desc> --path /your/path` | Specify output directory |
| `!task <desc> --cn` | Use cn CLI (fully autonomous, no clicking) |
| `!vscode ping` | Check VS Code bridge on PC |
| `!vscode ls <path>` | List directory on PC |
| `!vscode read <path>` | Read file from PC |
| `!vscode write <path> <content>` | Write file to PC |
| `!vscode run <cmd>` | Run shell command on PC |

### Android Builder
| Command | Description |
|---------|-------------|
| `!android <description>` | Build Android app via Gemini API |
| `!android stop` | Halt current build |
| `!android status` | Show build phase and iteration count |
| `!android ping` | Check Gemini + VS Code bridge |

### Calendar & Email
| Command | Description |
|---------|-------------|
| `!addevent \| title \| YYYY-MM-DD \| HH:MM` | Add calendar event |
| `!getevents \| start \| end` | Get calendar events |
| `!email unread` | Check unread email |
| `!email send \| to \| subject \| body` | Send email |

### Skills
| Command | Description |
|---------|-------------|
| `!skill install` | Scan and index all skills |
| `!skill search <query>` | Search skills by keyword |
| `!skill list` | List installed skills |
| `!skill count` | Count skills |

### System & Debug
| Command | Description |
|---------|-------------|
| `!tools` | List all registered tools |
| `!latency` | Measure warm-path model response time |
| `!modelinfo` | Show current model + config |
| `!audit` | Show last 20 tool call logs |
| `!help` | Full command list |
| `!cast volume 50` | Set Chromecast volume |
| `!cast mute / unmute` | Mute/unmute Chromecast |

Natural language also works for calendar, email, scrape, browse, and task triggers.

---

## AI Models

| Model | Size | Provider | Role |
|-------|------|----------|------|
| `qwen2.5:0.5b` | 394MB | Ollama (Pi) | Default chat — fast, snappy replies |
| `qwen2.5:1.5b` | 986MB | Ollama (Pi) | Reasoning, planning |
| `qwen2.5-coder:3b` | 1.9GB | Ollama (Pi) | Code generation (Pi-side fallback) |
| `gemma3:4b` | 2.5GB | Ollama (Pi) | Design + summarization |
| `Qwen2.5-Coder-14B` | 9GB Q4 | LM Studio (PC) | Heavy code, MCP agent orchestration |
| `Qwen2.5-Coder-3B` | 2.1GB Q4 | LM Studio (PC) | Inline autocomplete in VS Code |

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

See **[docs/MCP.md](docs/MCP.md)** for the full reference.

---

## Skill System

Every `!task` command automatically injects relevant skills from the 978-skill library into the SPEC before Continue builds. When 5 or more candidate skills are found, Jeeves sends a numbered menu to Discord so you can pick which ones to include.

```
📘 Candidate skills found (6):
1. pygame-2d-games
2. game-development
3. python-patterns
4. oop-design
5. collision-detection
6. sprite-animation

Reply with numbers (e.g. "1,3"), "all", or Enter to auto-select top 3.
```

See **[docs/SKILLS.md](docs/SKILLS.md)** for the full reference.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/INSTALL.md](docs/INSTALL.md) | Full step-by-step installation guide |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Server config, memory, personas, models |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, request lifecycle, streaming |
| [docs/AUTONOMOUS_BUILD.md](docs/AUTONOMOUS_BUILD.md) | !task pipeline — coding_agent, VS Code bridge, Continue |
| [docs/CONTINUE.md](docs/CONTINUE.md) | Continue + LM Studio setup and usage |
| [docs/COPILOT.md](docs/COPILOT.md) | GitHub Copilot alternative setup |
| [docs/MCP.md](docs/MCP.md) | MCP layer — registry, client, agent mode, tool catalogue |
| [docs/SKILLS.md](docs/SKILLS.md) | Skill system — library, injector, custom skills |
| [docs/BROWSER.md](docs/BROWSER.md) | Pinchtab browser tool — commands and setup |
| [docs/SCRAPE.md](docs/SCRAPE.md) | Web scraping — content, price, search |
| [docs/ANDROID.md](docs/ANDROID.md) | Android builder via Gemini API |
| [docs/CLAUDE_CODE_INTEGRATION.md](docs/CLAUDE_CODE_INTEGRATION.md) | Route Claude Code through Jeeves (zero API cost) |
| [docs/DISCOVERY.md](docs/DISCOVERY.md) | Discovery Layer — auto-index GitHub repos in /skills and /tools |

---

## Discovery Layer

Jeeves automatically indexes any GitHub repository you drop into `/skills/` or `/tools/` directories. The Discovery Layer scans these folders on a schedule, classifies each repo by type (skill, tool, or mixed), and displays them in the dashboard with search, filter, and stats.

```
┌─────────────────────────────────────────────────────────────────┐
│ Systemd timer (every 5 min)                                     │
│           ↓                                                      │
│ discover.py scans /skills/* and /tools/*                        │
│   • Classifies by Option C hybrid rules                          │
│   • Computes size and mtime recursively                         │
│   • Writes discovery/index.json atomically                      │
│           ↓                                                      │
│ HTTP API (/api/discovery) + Dashboard Panel (DiscoveryView.js)  │
│   • Search by name, path, or .md files                          │
│   • Filter by type (skill, tool, mixed) or source               │
│   • View metadata: file counts, size, modified date             │
│           ↓                                                      │
│ Zero impact on skill_injector, tool_registry, skills_manager    │
└─────────────────────────────────────────────────────────────────┘
```

**Classification rules (Option C hybrid):**
- `SKILL.md` at depth 1 → **skill**
- Else `README.md` → **skill**
- Else ≥2 `.md` files → **skill**
- Else 1 `.md` file → **skill**
- Else `.py` files only → **tool**
- Else both `.md` + `.py` → **mixed**
- Else → skip (ignored)

See **[docs/DISCOVERY.md](docs/DISCOVERY.md)** for full technical reference.

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
- [x] Tool registry — priority-ordered extensible dispatch
- [x] Skill auto-injection with interactive Discord selection
- [x] Android builder via Gemini 2.0 Flash
- [x] MarkItDown universal document ingestion
- [ ] MCP dashboard tool timeline UI
- [ ] Scheduled price monitoring via BrainDB jobs
- [ ] Voice input via Whisper

---

## License

MIT — see [LICENSE](LICENSE)
