# Installation Guide

## Prerequisites

- Raspberry Pi 5 (8GB recommended)
- NVMe SSD mounted at `/mnt/storage` (or adjust paths)
- Debian Trixie / Raspberry Pi OS Bookworm 64-bit
- Python 3.11+
- A Discord bot token
- Ollama installed

---

## 1. Install Ollama

```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

Pull the required models:

```bash
ollama pull qwen2.5:0.5b      # default chat — always warm (fastest)
ollama pull qwen2.5:1.5b      # reasoning / fallback for !task
ollama pull qwen2.5-coder:3b  # code generation (Pi-side fallback)
ollama pull gemma3:4b          # design + summarization
```

Keep models warm permanently:

```bash
sudo systemctl edit ollama
# Add under [Service]:
# Environment="OLLAMA_KEEP_ALIVE=-1"
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## 2. Clone and Set Up

```bash
cd /mnt/storage
git clone https://github.com/GeneralMillz/pi-claw.git pi-assistant
cd pi-assistant

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## 3. Configure Environment

```bash
cp .env.example .env
nano .env
```

Fill in:

```env
DISCORD_TOKEN=your_bot_token_here
GOOGLE_CREDENTIALS_PATH=/mnt/storage/pi-assistant/google_credentials.json
```

---

## 4. Configure Your Server

Copy and edit the example server config:

```bash
cp config/servers/example.json config/servers/YOUR_SERVER_ID.json
nano config/servers/YOUR_SERVER_ID.json
```

```json
{
  "name": "my_server",
  "mode": "founder",
  "allowed_channels": ["jeeves"],
  "activation_word": "jeeves",
  "tools_enabled": true,
  "persona_file": "config/personas/jeeves_founder.txt"
}
```

Get your server ID: Discord → Server Settings → Widget → Server ID.

---

## 5. Set Up Systemd Services

### Pi Assistant Daemon

```bash
sudo nano /etc/systemd/system/pi-assistant.service
```

```ini
[Unit]
Description=Jerry's Pi Assistant (Local LLM)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/mnt/storage/pi-assistant
ExecStart=/mnt/storage/pi-assistant/venv/bin/python3 -m assistant.http_server
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1
Environment=PATH=/mnt/storage/pi-assistant/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=VIRTUAL_ENV=/mnt/storage/pi-assistant/venv
Environment=HOME=/home/pi
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Discord Bot

```bash
sudo nano /etc/systemd/system/pi-discord-bot.service
```

```ini
[Unit]
Description=Pi Assistant Discord Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/mnt/storage/pi-assistant
ExecStart=/mnt/storage/pi-assistant/venv/bin/python3 /mnt/storage/pi-assistant/discord_modular.py
Restart=on-failure
RestartSec=30
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/mnt/storage/pi-assistant/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable pi-assistant pi-discord-bot
sudo systemctl start pi-assistant
sleep 30   # wait for model warmup
sudo systemctl start pi-discord-bot
```

---

## 6. Initialize the Database

The database initializes automatically on first start. Verify:

```bash
sqlite3 /mnt/storage/pi-assistant/data/jeeves.db ".tables"
```

You should see: `conversations`, `projects`, `files`, `tasks`, `jobs`, `tool_audit`, `memory_notes`, etc.

---

## 7. Create the Custom Skills Directory

```bash
mkdir -p /mnt/storage/pi-assistant/skills/custom
```

This is where your own `SKILL.md` files go. The directory must exist even if empty or `skill_injector.py` will log a warning.

---

## 8. Install the Skill Libraries

Clone the community libraries:

```bash
cd /mnt/storage/pi-assistant/skills
git clone https://github.com/sickn33/antigravity-awesome-skills
git clone https://github.com/alirezarezvani/claude-skills
git clone https://github.com/K-Dense-AI/claude-scientific-skills
```

Then from Discord (once the bot is running):

```
jeeves !skill install
```

---

## 9. Set Up VS Code Bridge (PC Side)

See **[CONTINUE.md](CONTINUE.md)** for full instructions.

Short version:

```powershell
# On your PC
cd G:\Jeeves\vscode-bridge
npm install
node server.js   # keep this running
```

Install the VS Code extension:

```powershell
$ext = "$env:USERPROFILE\.vscode\extensions\jeeves-copilot-bridge"
New-Item -ItemType Directory -Force -Path $ext
Copy-Item "G:\Jeeves\vscode-bridge\extension.js" "$ext\extension.js" -Force
Copy-Item "G:\Jeeves\vscode-bridge\package.json"  "$ext\package.json"  -Force
```

Reload VS Code: `Ctrl+Shift+P` → `Developer: Reload Window`

---

## 10. Test It

```bash
# Check daemon is up
curl http://localhost:8001/ask \
  -H "Content-Type: application/json" \
  -d '{"user":"ping","server_id":"test","channel_name":"test"}'

# Verify tool registry loaded
sudo journalctl -u pi-assistant -n 20 | grep TOOLS

# Check Discord bot
sudo journalctl -u pi-discord-bot -f
```

In Discord:

```
jeeves hello
jeeves !tools
jeeves !task build a snake game in pygame
```

---

## Deploying Updated Files

After any session that produces new Pi-side files, the standard deploy sequence:

```bash
# Copy to service location
cp coding_agent.py  /mnt/storage/pi-assistant/tools/coding_agent.py
cp skill_injector.py /mnt/storage/pi-assistant/tools/skill_injector.py
cp http_server.py   /mnt/storage/pi-assistant/assistant/http_server.py
cp tool_registry.py /mnt/storage/pi-assistant/assistant/tool_registry.py
cp brain_pipeline.py /mnt/storage/pi-assistant/assistant/brain_pipeline.py

# Restart
sudo systemctl restart pi-assistant.service

# Verify no errors
journalctl -u pi-assistant.service -f
```

---

## Troubleshooting

**Bot restarts every 2 minutes:**
```bash
grep "Restart" /etc/systemd/system/pi-discord-bot.service
# Must be: Restart=on-failure  (NOT Restart=always)
```

**`!task` falls through to LLM chat instead of building:**
```bash
# Verify tool_registry is loaded and brain_pipeline imports it
python3 -c "from assistant.tool_registry import registry; print(registry.list_tools())"
# Should print coding-agent and tools-list
```

**`[TOOLS] Handler 'coding-agent' raised: name 'Path' is not defined`:**
```bash
grep "from pathlib" /mnt/storage/pi-assistant/tools/coding_agent.py
# Must show: from pathlib import Path
```

**Streaming updates not appearing in Discord:**
```bash
sudo journalctl -u pi-assistant --since "5 min ago" | grep NOTIFY
# Should show 200 responses
```

**Model timing out:**
```bash
ollama list           # verify models are present
ollama run qwen2.5:1.5b "ping"   # test manually
```

**Database errors:**
```bash
sqlite3 /mnt/storage/pi-assistant/data/jeeves.db ".schema" | head -20
```

**Skill menu appears but build never continues:**

The `deliver_reply()` path in `http_server.py` v2.1.2 must be present. Check:
```bash
grep "deliver_reply\|v2.1.2" /mnt/storage/pi-assistant/assistant/http_server.py
```
