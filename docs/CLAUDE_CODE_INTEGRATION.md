# Claude Code + Jeeves Integration

This documents how to run Claude Code locally using Jeeves (Raspberry Pi) as the LLM backend — zero Anthropic API costs for chat.

## How It Works

Claude Code normally calls `api.anthropic.com`. By setting `ANTHROPIC_BASE_URL`, we redirect it to Jeeves' OpenAI/Anthropic-compatible API running on the Pi at port 8002.

```
Claude Code (Windows PC)
    ↓  POST /v1/messages
Jeeves openai_server.py (Pi :8002)
    ↓  brain.process()
qwen2.5:1.5b via Ollama (Pi)
    ↓  response
Claude Code displays answer
```

## Setup (Windows — one time)

```powershell
# Set permanently (survives restarts)
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://192.168.1.170:8002", "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaa", "User")
```

Open a **new** PowerShell window after setting, then:

```powershell
cd G:\Jeeves
claude
# When prompted "Use this API key?" → choose 1 (Yes)
```

## Pi Services

```bash
# OpenAI/Anthropic-compatible wrapper (port 8002)
sudo systemctl status jeeves-openai
sudo systemctl restart jeeves-openai
sudo journalctl -u jeeves-openai -f

# Main Jeeves daemon (port 8001)
sudo systemctl status jeeves
sudo systemctl restart jeeves
```

## Key Files on Pi

| File | Purpose |
|------|---------|
| `/mnt/storage/pi-assistant/openai_server.py` | API wrapper — handles Claude Code requests |
| `/mnt/storage/pi-assistant/assistant/assistant_tools.py` | Tool dispatcher — all failures silent |
| `/mnt/storage/pi-assistant/tools/calendar/calendar_nlp.py` | Calendar NLP — strict matching only |
| `/mnt/storage/pi-assistant/tools/calendar/assistant_calendar.py` | Calendar — `calendar_enabled = False` |

## How openai_server.py Works

Claude Code sends a massive system prompt on every message. The server:

1. **Strips `<system-reminder>` blocks** — injected metadata Claude Code adds to user messages
2. **Skips system/tool roles** — the giant Claude Code system prompt is too large for a 1.5b model
3. **Passes only USER/ASSISTANT turns** to Jeeves brain
4. **Returns Anthropic SSE format** — `message_start` → `content_block_delta` → `message_stop`

```python
# What Claude Code sends:
USER: <system-reminder>...968 lines of instructions...</system-reminder>hey jeeves

# What Jeeves receives:
USER: hey jeeves
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `model not found` error | Set env vars, choose option 1 (Yes) when prompted |
| Empty responses | Check `brain.process()` not `brain.stream()` in openai_server.py |
| System prompt echoed back | `import re` missing, or `_strip_system_reminders` not applied |
| Calendar errors on every message | `calendar_enabled = False` in assistant_calendar.py |
| `[WARN] No server config for openai` | Harmless — create `config/servers/openai.json` to silence |

## Optional: Create openai server config

To silence the `[WARN] No server config for openai` warning, create on the Pi:

```bash
mkdir -p /mnt/storage/pi-assistant/config/servers
cat > /mnt/storage/pi-assistant/config/servers/openai.json << 'EOF'
{
  "name": "Claude Code",
  "short_reply_mode": true,
  "identity_override": true
}
EOF
```
