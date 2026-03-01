#!/usr/bin/env bash
# ============================================================
# Jeeves — Pi Assistant Installer
# Tested on: Debian Trixie, Raspberry Pi OS Bookworm 64-bit
# Hardware:   Raspberry Pi 5 (8GB), NVMe SSD
# ============================================================
set -e

INSTALL_DIR="/mnt/storage/pi-assistant"
VENV="$INSTALL_DIR/venv"
SERVICE_USER="${SUDO_USER:-pi}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "  🤵 Jeeves Pi Assistant Installer"
echo "  ================================"
echo ""

# ── Check root ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Run as root: sudo ./install.sh"
fi

# ── Check Pi 5 ────────────────────────────────────────────────────────────────
if grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
    success "Raspberry Pi 5 detected"
else
    warn "Not a Pi 5 — install will continue but performance may differ"
fi

# ── Install system packages ───────────────────────────────────────────────────
info "Installing system packages..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv git sqlite3 curl

# ── Install Ollama ────────────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
    success "Ollama already installed"
else
    info "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    success "Ollama installed"
fi

# ── Create install directory ──────────────────────────────────────────────────
info "Setting up $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data"
mkdir -p "$INSTALL_DIR/config/servers"
mkdir -p "$INSTALL_DIR/config/personas"
mkdir -p "$INSTALL_DIR/config/history"
mkdir -p "$INSTALL_DIR/config/lore"
mkdir -p "$INSTALL_DIR/memory"
mkdir -p "$INSTALL_DIR/logs"

# Copy files if running from repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    info "Copying files from repo..."
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true
fi

# ── Set up Python venv ────────────────────────────────────────────────────────
info "Creating Python virtual environment..."
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$INSTALL_DIR/requirements.txt" -q
success "Python environment ready"

# ── Pull Ollama models ────────────────────────────────────────────────────────
info "Pulling Ollama models (this will take a while)..."
echo "  → qwen2.5:1.5b  (core chat, 1.1GB)"
ollama pull qwen2.5:1.5b
echo "  → gemma3:4b     (task planning, 3.3GB)"
ollama pull gemma3:4b
echo "  → gemma2:2b     (summarization, 1.6GB)"
ollama pull gemma2:2b
echo ""
warn "Optional: Pull larger models for better code generation"
warn "  ollama pull qwen2.5-coder:7b   (4.7GB)"
warn "  ollama pull qwen2.5-coder:3b   (1.9GB, faster)"
echo ""

# ── Configure .env ────────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_DIR/.env" ]; then
    info "Creating .env from example..."
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
    warn "Edit $INSTALL_DIR/.env and add your DISCORD_TOKEN"
fi

# ── Create default server config ─────────────────────────────────────────────
if [ ! "$(ls -A $INSTALL_DIR/config/servers/ 2>/dev/null)" ]; then
    info "Creating example server config..."
    cat > "$INSTALL_DIR/config/servers/YOUR_SERVER_ID.json" << 'EOF'
{
  "name": "my_server",
  "mode": "founder",
  "allowed_channels": ["jeeves"],
  "activation_word": "jeeves",
  "tools_enabled": true,
  "persona_file": "config/personas/jeeves_founder.txt"
}
EOF
    warn "Rename config/servers/YOUR_SERVER_ID.json to your actual Discord server ID"
fi

# ── Install systemd services ──────────────────────────────────────────────────
info "Installing systemd services..."

cat > /etc/systemd/system/pi-assistant.service << EOF
[Unit]
Description=Jerry's Pi Assistant (Local LLM)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV/bin/python3 -m assistant.http_server
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1
Environment=PATH=$VENV/bin:/usr/local/bin:/usr/bin:/bin
Environment=VIRTUAL_ENV=$VENV
Environment=HOME=/home/$SERVICE_USER
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/pi-discord-bot.service << EOF
[Unit]
Description=Pi Assistant Discord Bot
After=network-online.target pi-assistant.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV/bin/python3 $INSTALL_DIR/discord_modular.py
Restart=on-failure
RestartSec=30
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=$INSTALL_DIR/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pi-assistant pi-discord-bot
success "Systemd services installed"

# ── Fix permissions ───────────────────────────────────────────────────────────
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Jeeves installation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Add your Discord token:"
echo "     nano $INSTALL_DIR/.env"
echo ""
echo "  2. Create your server config:"
echo "     cp $INSTALL_DIR/config/servers/YOUR_SERVER_ID.json \\"
echo "        $INSTALL_DIR/config/servers/<your_discord_server_id>.json"
echo "     nano $INSTALL_DIR/config/servers/<your_discord_server_id>.json"
echo ""
echo "  3. Start the services:"
echo "     sudo systemctl start pi-assistant"
echo "     sleep 30"
echo "     sudo systemctl start pi-discord-bot"
echo ""
echo "  4. Check logs:"
echo "     sudo journalctl -u pi-assistant -f"
echo "     sudo journalctl -u pi-discord-bot -f"
echo ""
echo "  5. Test in Discord:"
echo "     jeeves hello"
echo "     jeeves !task build a snake game in pygame"
echo ""
echo "  Full docs: docs/INSTALL.md"
echo ""
