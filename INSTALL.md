# Jeeves — Installation Guide

> Tested on: Raspberry Pi 5 (8GB), Ubuntu 24.04 LTS 64-bit  
> Also works on: Raspberry Pi 4 (4GB+), Raspberry Pi OS Bookworm 64-bit

---

## Prerequisites

- Raspberry Pi 4 or 5 (4GB RAM minimum, 8GB recommended)
- Ubuntu 24 or Raspberry Pi OS Bookworm — **64-bit only**
- Internet connection for initial setup
- A Discord account and a server you own/admin
- (Optional) Windows or Linux PC on the same LAN for VS Code Bridge + Copilot

---

## Step 1 — System Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  python3 python3-pip python3-venv python3-dev \
  git curl wget \
  build-essential \
  libssl-dev libffi-dev \
  ffmpeg nano
```

---

## Step 2 — Storage Setup (Recommended)

NVMe SSD gives much better model load times. If using one, mount it:

```bash
sudo mkdir -p /mnt/storage
lsblk                             # find your NVMe device name
sudo mkfs.ext4 /dev/nvme0n1       # format (replace nvme0n1 with yours)
sudo mount /dev/nvme0n1 /mnt/storage
echo '/dev/nvme0n1 /mnt/storage ext4 defaults 0 2' | sudo tee -a /etc/fstab
```

If you skip this, the installer will fall back to `~/jeeves`.

---

## Step 3 — Install Ollama

```bash
curl -fsSL https://ollama.ai/install.sh | sh
sudo systemctl enable ollama
sudo systemctl start ollama
```

Verify:
```bash
ollama --version
curl http://127.0.0.1:11434/api/tags
```

---

## Step 4 — Pull AI Models

```bash
ollama pull qwen2.5:1.5b       # core model — required
ollama pull gemma2:2b           # design summarizer — required
ollama pull qwen2.5-coder:3b   # code generation — required for !task
```

This will take a few minutes depending on your connection. Verify:
```bash
ollama list
```

---

## Step 5 — Clone and Install Jeeves

```bash
cd /mnt/storage    # or cd ~ if no NVMe
git clone https://github.com/yourusername/jeeves.git pi-assistant
cd pi-assistant

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## Step 6 — Create Your Environment File

```bash
cp .env.example .env
nano .env
```

At minimum, fill in `DISCORD_TOKEN`. Everything else is optional depending on which tools you want.

---

## Step 7 — Create a Discord Bot

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications)
2. **New Application** → give it a name (e.g. "Jeeves")
3. Go to **Bot** tab → **Add Bot**
4. Under **Privileged Gateway Intents**, enable:
   - ✅ Message Content Intent
   - ✅ Server Members Intent
5. Copy the bot **Token** → paste into `.env` as `DISCORD_TOKEN`
6. Go to **OAuth2 → URL Generator**:
   - Scopes: `bot`
   - Bot Permissions: `Send Messages`, `Read Message History`, `View Channels`
7. Open the generated URL → invite the bot to your server

---

## Step 8 — Configure Your Server

Find your Discord server ID:  
Discord → Settings → Advanced → enable **Developer Mode** → right-click your server → **Copy Server ID**

```bash
cp config/servers/example.json config/servers/YOUR_SERVER_ID.json
nano config/servers/YOUR_SERVER_ID.json
```

Minimal config to get started:
```json
{
  "name": "my_server",
  "mode": "founder",
  "allowed_channels": ["jeeves"],
  "activation_word": "jeeves",
  "tools_enabled": true,
  "persona_file": "default.txt",
  "short_reply_mode": true
}
```

Create the channel in your Discord server:
- Add a text channel named `jeeves` (or whatever you set in `allowed_channels`)

---

## Step 9 — Add Your Memory File (Optional but Recommended)

```bash
cp memory/personal.example.md memory/YOUR_SERVER_ID.md
nano memory/YOUR_SERVER_ID.md
```

Then register it in `assistant/memory_loader.py`:
```python
_MEMORY_MAP = {
    "YOUR_SERVER_ID": "YOUR_SERVER_ID",
}
```

This file gets injected into every AI prompt — add anything you want the assistant to always know about you.

---

## Step 10 — Google Calendar (Optional)

1. [console.cloud.google.com](https://console.cloud.google.com) → New Project
2. Enable **Google Calendar API**
3. Create **OAuth 2.0 credentials** (Desktop app type)
4. Download `credentials.json` → save to `config/google_credentials.json`
5. Authorize:
```bash
source venv/bin/activate
python3 tools/calendar/auth.py
```
Follow the browser prompt. This creates `config/google_token.json`.

---

## Step 11 — Install Systemd Services

```bash
# Edit the service files to match your username and path
nano systemd/pi-assistant.service.template
nano systemd/pi-discord-bot.service.template

# Install
sudo cp systemd/pi-assistant.service.template /etc/systemd/system/pi-assistant.service
sudo cp systemd/pi-discord-bot.service.template /etc/systemd/system/pi-discord-bot.service

sudo systemctl daemon-reload
sudo systemctl enable pi-assistant.service pi-discord-bot.service
sudo systemctl start pi-assistant.service pi-discord-bot.service
```

Check status:
```bash
sudo systemctl status pi-assistant.service
sudo systemctl status pi-discord-bot.service
```

Watch logs:
```bash
sudo journalctl -u pi-assistant -f
sudo journalctl -u pi-discord-bot -f
```

---

## Step 12 — Test It

```bash
# Test the daemon directly
curl -s -X POST http://127.0.0.1:8001/ask \
  -H "Content-Type: application/json" \
  -d '{"user": "hi", "server_id": "YOUR_SERVER_ID", "channel_name": "jeeves"}'
```

Should return `{"type": "chat", "content": "Hello! ..."}` within a few seconds.

Then say `jeeves hi` in your Discord channel.

---

## Step 13 — VS Code Bridge (Optional — Windows PC)

Required for `!vscode` commands and Copilot orchestration.

On your **Windows PC**:

```powershell
# Node.js required — download from nodejs.org if needed
node --version

# Copy the bridge files to your PC
# (download vscode-bridge/ folder from this repo)
cd C:\wherever\you\put\it\vscode-bridge
npm install

# Allow port 5055 through Windows Firewall
netsh advfirewall firewall add rule name="Jeeves Bridge" dir=in action=allow protocol=TCP localport=5055

# Start the bridge
node server.js
```

Update your Pi config with your PC's LAN IP:
```bash
# In tools/vscode/vscode_tools.py
_DEFAULT_HOST = "http://YOUR_PC_LAN_IP:5055"

# In tools/coding_agent.py
VSCODE_HOST = "http://YOUR_PC_LAN_IP:5055"
```

Test from Pi:
```bash
curl -s http://YOUR_PC_LAN_IP:5055/ping
```

**Auto-start on Windows login (PowerShell as Admin):**
```powershell
$action  = New-ScheduledTaskAction -Execute "node" -Argument "C:\path\to\vscode-bridge\server.js" -WorkingDirectory "C:\path\to\vscode-bridge"
$trigger = New-ScheduledTaskTrigger -AtLogon
Register-ScheduledTask -TaskName "Jeeves Bridge" -Action $action -Trigger $trigger -RunLevel Highest
```

---

## Morning Briefing (Optional)

Posts a daily summary to Discord at 8am:

```bash
crontab -e
# Add:
0 8 * * * /mnt/storage/pi-assistant/venv/bin/python3 /mnt/storage/pi-assistant/tasks/morning_briefing.py >> /var/log/jeeves-briefing.log 2>&1
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Bot doesn't respond | Check `allowed_channels` in server config matches your channel name |
| `DISCORD_TOKEN not set` | Check `.env` is in project root and token is correct |
| Slow responses (30-40s) | Check `fact_path` in server config — remove if pointing at wrong directory |
| Ollama not responding | `sudo systemctl restart ollama` |
| Model not found | `ollama pull qwen2.5:1.5b` |
| VS Code bridge timeout | Check firewall rule, confirm `node server.js` is running on PC |
| BrokenPipeError in logs | Harmless — notify poller disconnects between polls, safely ignored |

---

## Updating

```bash
cd /path/to/pi-assistant
git pull
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart pi-assistant.service
sudo systemctl restart pi-discord-bot.service
```
