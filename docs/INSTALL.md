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
ollama pull qwen2.5:1.5b      # core chat — always warm
ollama pull gemma3:4b          # task planning
ollama pull qwen2.5-coder:7b   # code generation
ollama pull gemma2:2b          # summarization / QA
```

Keep models warm permanently:

```bash
sudo systemctl edit ollama
# Add:
# [Service]
# Environment="OLLAMA_KEEP_ALIVE=-1"
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
cp example.json config/servers/YOUR_SERVER_ID.json
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

The database initializes automatically on first start. Verify it was created:

```bash
sqlite3 /mnt/storage/pi-assistant/data/jeeves.db ".tables"
```

You should see: `conversations`, `projects`, `files`, `tasks`, `jobs`, `project_files`, `project_symbols`, etc.

Run the project index migration if needed:

```bash
sqlite3 /mnt/storage/pi-assistant/data/jeeves.db < assistant/003_project_index.sql
```

---

## 7. Set Up VS Code Bridge (PC Side)

See **[COPILOT.md](COPILOT.md)** for full instructions.

Short version:

```powershell
# On your PC
cd G:\Jeeves\vscode-bridge
npm install
node server.js   # keep this running
```

Install the VS Code extension:

```powershell
cp extension.js "$env:USERPROFILE\.vscode\extensions\jeeves-copilot-bridge\extension.js" -Force
```

Reload VS Code: `Ctrl+Shift+P` → `Developer: Reload Window`

---

## 8. Test It

```bash
# Check daemon is up
curl http://localhost:8001/ask -d '{"user":"ping","server_id":"test","channel_name":"test"}'

# Check Discord bot
sudo journalctl -u pi-discord-bot -f
```

In Discord:
```
jeeves !ping
jeeves hello
jeeves !task build a snake game in pygame
```

---

## Troubleshooting

**Bot restarts every 2 minutes:**
```bash
grep "Restart" /etc/systemd/system/pi-discord-bot.service
# Should be: Restart=on-failure (NOT Restart=always)
```

**Streaming updates not appearing in Discord:**
```bash
sudo journalctl -u pi-assistant --since "5 min ago" | grep NOTIFY
# Should show 200 responses
```

**Model timing out:**
```bash
ollama list   # verify models are present
ollama run qwen2.5:1.5b "ping"   # test manually
```

**Database errors:**
```bash
sqlite3 /mnt/storage/pi-assistant/data/jeeves.db ".schema" | head -20
# Re-run migrations if tables are missing
```
