# Jeeves + GitHub Copilot Integration

Jeeves acts as an **orchestrator**. Copilot does the actual **implementation**.

---

## How It Works

```
You (Discord):   jeeves !task build a flask REST API with JWT auth
                          │
Jeeves:          Plans architecture with local AI (qwen2.5:1.5b)
                 Writes SPEC.md to your project folder on your PC
                 Opens VS Code with the project
                          │
You (VS Code):   Ctrl+Shift+I → Agent mode → @workspace implement SPEC.md
                          │
Copilot:         Reads SPEC.md
                 Creates all files
                 Runs and tests the code
                 Fixes errors automatically
```

---

## Requirements

- GitHub Copilot (free tier or subscription)
- VS Code with `github.copilot-chat` extension
- VS Code Bridge running on your PC

Verify Copilot Chat is installed:
```powershell
code --list-extensions | findstr -i copilot
# Expected: github.copilot-chat
```

---

## Setup

1. Follow [docs/INSTALL.md](INSTALL.md) Step 13 to set up the VS Code Bridge
2. Update your PC's LAN IP in `tools/vscode/vscode_tools.py` and `tools/coding_agent.py`
3. Test: `!vscode ping` in Discord

---

## Usage

```
!task build a pygame side scroller with enemies and scoring
!task create a REST API with user auth --path C:\projects\myapi
!task build a React dashboard for displaying CSV data
```

Natural language triggers (no `!task` needed):
> "jeeves build me a web scraper for product prices"  
> "jeeves create a Discord bot that posts weather daily"  
> "jeeves write a script to batch resize images"

---

## What Jeeves Creates

Example `SPEC.md` for `!task build a flask REST API`:

```markdown
# Task Specification

## Task
Build a flask REST API with user authentication

## Implementation Plan
- Files: app.py, models.py, auth.py, requirements.txt
- Libraries: Flask, Flask-JWT-Extended, SQLAlchemy, bcrypt
- Architecture: Blueprint-based, JWT tokens, SQLite for dev
- Order: models → auth routes → protected routes → tests

## Requirements
- Implement the task fully and completely
- Create all necessary files
- All code must be working and runnable
- Include all imports and dependencies

## Instructions for Copilot
@workspace Read this spec and implement everything described above.
Create all files, install any needed packages, and make sure the code runs.
```

---

## Copilot Workflow in VS Code

After Jeeves opens VS Code:

1. **`Ctrl+Shift+I`** — open Copilot Chat
2. Click the mode dropdown → select **Agent**
3. Type: `@workspace implement SPEC.md`
4. Press Enter

Copilot will create a todo list, generate all files, run the code, and fix errors.

---

## Discord Updates During Task

```
⚙️ Task started — streaming updates incoming...
🤖 Task: build a flask REST API with JWT auth
📁 Project: C:\projects\flask_rest_api_with_jwt
📋 Planning with AI...
✅ Plan ready (8200ms)
📝 Writing SPEC.md for Copilot...
✅ SPEC.md written.
🚀 Opening project for Copilot...
✅ VS Code opened with project and SPEC.md.
**Copilot is ready:**
1. Open Copilot Chat (Ctrl+Shift+I)
2. Switch to Agent mode
3. Type: @workspace implement SPEC.md
🏁 Jeeves done. Copilot takes it from here.
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| VS Code doesn't open | Confirm bridge is running: `curl http://YOUR_PC_IP:5055/ping` |
| SPEC.md not created | Check `/write` endpoint — confirm output directory exists |
| Copilot doesn't pick up SPEC.md | Ensure you're in **Agent** mode (not Ask mode) |
| `@workspace` not working | Open the folder as a workspace: File → Open Folder |
| 120s planning time | Normal on first run — model cold-loading. Subsequent tasks faster. |
