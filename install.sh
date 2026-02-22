#!/usr/bin/env bash
# ============================================================
# Jeeves Installer
# Raspberry Pi 5 / Ubuntu 24 / Raspberry Pi OS Bookworm 64-bit
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "  ╔══════════════════════════════════╗"
echo "  ║        🤵 Jeeves Installer        ║"
echo "  ╚══════════════════════════════════╝"
echo ""

# ── Root check ────────────────────────────────────────────────────────────────
[ "$EUID" -eq 0 ] && error "Do not run as root. Run as your normal user."

# ── Detect install path ───────────────────────────────────────────────────────
if mountpoint -q /mnt/storage 2>/dev/null; then
  JEEVES_DIR="/mnt/storage/pi-assistant"
  info "NVMe detected — installing to /mnt/storage/pi-assistant"
else
  JEEVES_DIR="$HOME/pi-assistant"
  warn "No NVMe at /mnt/storage — installing to $HOME/pi-assistant"
fi
VENV="$JEEVES_DIR/venv"

# ── OS detection ──────────────────────────────────────────────────────────────
[ -f /etc/os-release ] && . /etc/os-release && info "OS: $PRETTY_NAME"
ARCH=$(uname -m)
info "Architecture: $ARCH"
[[ "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]] && warn "Unexpected arch: $ARCH"

# ── System packages ───────────────────────────────────────────────────────────
info "Installing system packages..."
sudo apt update -qq
sudo apt install -y \
  python3 python3-pip python3-venv python3-dev \
  git curl wget build-essential \
  libssl-dev libffi-dev ffmpeg nano \
  2>/dev/null
success "System packages installed."

# ── Python version ────────────────────────────────────────────────────────────
PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
info "Python $PY_VER"
[ "$PY_MINOR" -lt 11 ] && error "Python 3.11+ required. Got $PY_VER"
success "Python $PY_VER OK."

# ── Ollama ────────────────────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
  success "Ollama already installed."
else
  info "Installing Ollama..."
  curl -fsSL https://ollama.ai/install.sh | sh
  success "Ollama installed."
fi

sudo systemctl enable ollama 2>/dev/null || true
sudo systemctl start ollama 2>/dev/null || true

info "Waiting for Ollama to start..."
for i in {1..10}; do
  curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 2
done

curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && success "Ollama running." || error "Ollama failed to start. Try: sudo systemctl status ollama"

# ── AI Models ─────────────────────────────────────────────────────────────────
info "Pulling AI models (this may take several minutes on first run)..."

pull_model() {
  info "Pulling $1..."
  ollama pull "$1" && success "$1 ready." || warn "Could not pull $1 — run manually: ollama pull $1"
}

pull_model "qwen2.5:1.5b"
pull_model "gemma2:2b"
pull_model "qwen2.5-coder:3b"

# ── Clone / update repo ───────────────────────────────────────────────────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$SCRIPT_DIR" = "$JEEVES_DIR" ]; then
  info "Already in install directory — skipping clone."
else
  if [ -d "$JEEVES_DIR/.git" ]; then
    info "Jeeves already installed — pulling latest..."
    cd "$JEEVES_DIR" && git pull
  else
    info "Installing Jeeves to $JEEVES_DIR..."
    sudo mkdir -p "$JEEVES_DIR"
    sudo chown "$USER:$USER" "$JEEVES_DIR"
    cp -r "$SCRIPT_DIR/." "$JEEVES_DIR/"
  fi
fi

cd "$JEEVES_DIR"

# ── Python venv ───────────────────────────────────────────────────────────────
info "Creating Python virtual environment..."
python3 -m venv "$VENV"
source "$VENV/bin/activate"
pip install --upgrade pip -q
pip install -r requirements.txt -q
success "Python environment ready."

# ── Directories ───────────────────────────────────────────────────────────────
mkdir -p "$JEEVES_DIR/logs"
mkdir -p "$JEEVES_DIR/memory"
mkdir -p "$JEEVES_DIR/config/servers"
mkdir -p "$JEEVES_DIR/config/personas"
success "Directories created."

# ── .env ──────────────────────────────────────────────────────────────────────
if [ ! -f "$JEEVES_DIR/.env" ]; then
  cp "$JEEVES_DIR/.env.example" "$JEEVES_DIR/.env"
  warn ".env created — you must edit it before starting: nano $JEEVES_DIR/.env"
else
  info ".env already exists."
fi

# ── Memory file ───────────────────────────────────────────────────────────────
if [ ! -f "$JEEVES_DIR/memory/personal.example.md" ]; then
  warn "memory/personal.example.md not found — skipping."
fi

# ── Systemd services ──────────────────────────────────────────────────────────
info "Installing systemd services..."

install_service() {
  TEMPLATE="$JEEVES_DIR/systemd/$1.template"
  TARGET="/etc/systemd/system/$1"
  if [ -f "$TEMPLATE" ]; then
    sed "s|JEEVES_DIR|$JEEVES_DIR|g; s|VENV_DIR|$VENV|g; s|SERVICE_USER|$USER|g" \
      "$TEMPLATE" | sudo tee "$TARGET" >/dev/null
    success "$1 installed."
  else
    warn "Template $TEMPLATE not found — service not installed."
  fi
}

install_service "pi-assistant.service"
install_service "pi-discord-bot.service"

sudo systemctl daemon-reload
sudo systemctl enable pi-assistant.service pi-discord-bot.service 2>/dev/null || true

# ── Health check ──────────────────────────────────────────────────────────────
echo ""
info "Running health check..."
HEALTH_OK=true

curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 \
  && success "✓ Ollama running" || { warn "✗ Ollama not responding"; HEALTH_OK=false; }

ollama list 2>/dev/null | grep -q "qwen2.5:1.5b" \
  && success "✓ qwen2.5:1.5b ready" || { warn "✗ qwen2.5:1.5b missing"; HEALTH_OK=false; }

grep -q "your_discord_bot_token_here" "$JEEVES_DIR/.env" 2>/dev/null \
  && { warn "✗ .env not configured"; HEALTH_OK=false; } || success "✓ .env configured"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════╗"
[ "$HEALTH_OK" = true ] \
  && echo "  ║   ✅ Jeeves installed successfully!           ║" \
  || echo "  ║   ⚠️  Jeeves installed with warnings           ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit .env with your Discord token:"
echo "     nano $JEEVES_DIR/.env"
echo ""
echo "  2. Create your server config:"
echo "     cp $JEEVES_DIR/config/servers/example.json \\"
echo "        $JEEVES_DIR/config/servers/YOUR_SERVER_ID.json"
echo "     nano $JEEVES_DIR/config/servers/YOUR_SERVER_ID.json"
echo ""
echo "  3. Create your memory file (optional but recommended):"
echo "     cp $JEEVES_DIR/memory/personal.example.md \\"
echo "        $JEEVES_DIR/memory/YOUR_SERVER_ID.md"
echo "     nano $JEEVES_DIR/memory/YOUR_SERVER_ID.md"
echo ""
echo "  4. Start Jeeves:"
echo "     sudo systemctl start pi-assistant.service"
echo "     sudo systemctl start pi-discord-bot.service"
echo ""
echo "  5. Watch logs:"
echo "     sudo journalctl -u pi-assistant -f"
echo ""
echo "  Full guide: docs/INSTALL.md"
echo ""
