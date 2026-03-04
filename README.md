# 🤵 Jeeves

**A fully self-hosted AI assistant for Raspberry Pi 5**  
Lives in Discord. Controls your PC. Orchestrates GitHub Copilot. Browses the web. Builds Android apps.

[![Pi 5](https://img.shields.io/badge/Raspberry_Pi_5-8GB-red?logo=raspberry-pi)](https://www.raspberrypi.com)
[![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python)](https://python.org)
[![Discord](https://img.shields.io/badge/Discord-Bot-5865F2?logo=discord)](https://discord.com)
[![Ollama](https://img.shields.io/badge/Ollama-Local_LLM-black)](https://ollama.ai)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## What is Jeeves?

Jeeves is a production-grade, fully self-hosted AI assistant running on a **Raspberry Pi 5**. It connects to your Discord servers and gives you a personal AI that:

- 💬 **Chats** with persistent per-server memory and conversation history
- 📅 **Manages your calendar** (Google Calendar)
- 📧 **Reads and sends email** (IMAP/SMTP)
- 🎨 **Generates UI/UX design systems** with AI + Gemma summarization
- 🖥️ **Controls VS Code on your PC** over LAN — read, write, run files
- 🤖 **Orchestrates GitHub Copilot** — Jeeves plans, Copilot builds
- 🌐 **Browses the web headlessly** via Pinchtab — navigate, click, fill forms, screenshot, scrape
- 📱 **Builds Android apps autonomously** via direct Gemini API + VS Code bridge
- 📄 **Ingests any document** (PDF, Word, Excel, YouTube, HTML…) via MarkItDown
- 📡 **Streams live updates to Discord** during long-running tasks
- 📺 **Controls Chromecast** (volume, mute)
- 🧠 **Per-server persistent memory** — Jeeves remembers your context, projects, and preferences
- 📋 **Audit logs** every tool call
- ☀️ **Morning briefing** — daily digest of calendar + email + system stats

All AI runs **locally on your Pi**. No OpenAI API costs. No cloud dependency (except optional Gemini free tier for Android builds).

> **You can rename it.** "Jeeves" is just the default activation word and persona. Change it in your server config.

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
       ├── Tool layer            ← tools/assistant_tools.py
       │     ├── !task     ───────────────────────────────────┐
       │     ├── !email                                        │
       │     ├── !calendar                                     ▼
       │     ├── !design        VS Code Bridge (PC :5055)
       │     ├── !cast          /open /read /write /ls /run
       │     ├── !vscode  ───→  /copilot/task → SPEC.md → Copilot agent
       │     ├── !browse  ───→  Pinchtab :9867 → Chromium headless
       │     ├── !android ───→  Gemini API → file parser → VS Code bridge
       │     └── !markdownify → MarkItDown → BrainDB storage
       │
       └── Brain pipeline       ← Qwen 1.5b (always warm)
             ├── Per-server memory (SQLite BrainDB)
             ├── Fact injection
             └── Ollama /v1/chat/completions

Streaming:
  tool/agent → POST /notify → queue → Discord bot polls GET /notify → channel.send()
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
git clone https://github.com/GeneralMillz/pi-claw.git
cd pi-claw
chmod +x install.sh
./install.sh
```

Then follow the post-install steps printed by the installer.

Full guide: **[INSTALL.md](INSTALL.md)**

---

## Commands

### Core
| Command | Description |
|---------|-------------|
| `!task <description>` | Plan task + hand off to Copilot |
| `!task <desc> --path /your/path` | Specify output directory |
| `!latency` | Measure model response time |
| `!modelinfo` | Show AI model config |
| `!audit` | Show last 20 tool call logs |
| `!help` | Full command list |

### Email & Calendar
| Command | Description |
|---------|-------------|
| `!email unread` | Check unread email |
| `!email send \| to \| subject \| body` | Send email |
| `!addevent \| title \| YYYY-MM-DD \| HH:MM` | Add calendar event |
| `!getevents \| start \| end` | Get calendar events |

### VS Code & PC Control
| Command | Description |
|---------|-------------|
| `!vscode ping` | Check VS Code bridge |
| `!vscode ls <path>` | List directory on PC |
| `!vscode read <path>` | Read file from PC |
| `!vscode write <path> <content>` | Write file to PC |
| `!vscode run <cmd>` | Run shell command on PC |

### Browser (Pinchtab)
| Command | Description |
|---------|-------------|
| `!browse <url>` | Navigate and read page text |
| `!browse snap [url]` | List interactive elements with refs |
| `!browse click <ref>` | Click element (e0, e1…) |
| `!browse fill <ref> <text>` | Fill input field |
| `!browse press <key>` | Press key (Enter, Tab, Escape…) |
| `!browse scroll` | Scroll down |
| `!browse back` | Navigate back |
| `!browse screenshot` | Capture viewport as image |
| `!browse tabs` | List open tabs |
| `!browse eval <js>` | Run JavaScript |
| `!browse health` | Check Pinchtab status |

### Android Builder
| Command | Description |
|---------|-------------|
| `!android <description>` | Start autonomous Android app build |
| `!android stop` | Stop current build loop |
| `!android status` | Show build progress |
| `!android ping` | Check Gemini API + VS Code bridge |

### Document Ingestion
| Command | Description |
|---------|-------------|
| `!markdownify <url>` | Convert URL to Markdown (PDF, HTML, YouTube…) |
| `!markdownify` + attach file | Convert attached file |
| `!mdoc search <query>` | Search stored documents |
| `!mdoc get <doc_id>` | Retrieve a stored document |

### Design & Cast
| Command | Description |
|---------|-------------|
| `!design <project description>` | Generate UI/UX design system |
| `!cast volume 50` | Set Chromecast volume |
| `!cast mute / unmute` | Mute/unmute Chromecast |

Natural language also works for calendar, design, cast, task, and browse triggers.

---

## AI Models

| Model | Size | Purpose |
|-------|------|---------|
| `qwen2.5:1.5b` | 1.1GB | Core chat + planning (always warm) |
| `gemma2:2b` | 1.6GB | Design output summarization |
| `qwen2.5-coder:3b` | 1.9GB | Code generation (on-demand) |
| Gemini 2.0 Flash | cloud | Android app building (free tier) |

All local models run via [Ollama](https://ollama.ai). No API keys required for local inference.  
Gemini is optional — only needed for `!android` (free tier, 15 req/min).

---

## Documentation

| Doc | Contents |
|-----|----------|
| [INSTALL.md](INSTALL.md) | Full step-by-step installation guide |
| [CONFIGURATION.md](CONFIGURATION.md) | Server config, memory, personas, models |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, data flow, component breakdown |
| [COPILOT.md](COPILOT.md) | VS Code + GitHub Copilot orchestration setup |
| [BROWSER.md](BROWSER.md) | Pinchtab browser tool setup and all commands |
| [ANDROID.md](ANDROID.md) | Android Studio + Gemini API autonomous builder |

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
