# 📱 ANDROID.md — Android Builder (Gemini API)

Jeeves can autonomously build Android apps by calling the **Gemini API directly** from the Pi, then writing the generated files to your PC via the VS Code bridge. No mouse control. No UI automation. No clipboard tricks.

---

## How It Works

```
Discord  !android build a notes app with Room and MVVM
       │
       ▼
assistant/gemini_agent.py  (runs on Pi)
       │
       ├── POST generativelanguage.googleapis.com
       │         Gemini 2.0 Flash (free tier)
       │         ↓ returns structured response with ### FILE: blocks
       │
       ├── parse files:
       │     ### FILE: app/src/main/java/.../MainActivity.kt
       │     <file content>
       │     ### FILE: app/build.gradle.kts
       │     <file content>
       │
       ├── POST http://192.168.1.153:5055/write  (one per file)
       │         ↓ files land in G:\Jeeves\projects\<app-name>\
       │
       └── POST /notify  → Discord streams progress live
```

Gemini generates the code. The VS Code bridge writes it to disk. Jeeves streams each phase to Discord as it completes.

---

## Why Not UI Automation?

Early versions of this used `pyautogui` to click into Android Studio's Gemini panel. That approach was abandoned because:

- Required fragile coordinate calibration per screen resolution
- Couldn't reliably read Gemini's output from the clipboard
- Moving the mouse interrupted active work on the PC

The direct API approach is faster, more reliable, and completely non-intrusive to whatever you're doing on your PC.

---

## Prerequisites

### On the Pi
- `GEMINI_API_KEY` environment variable set (free at [aistudio.google.com](https://aistudio.google.com))
- `requests` library (already in the Jeeves venv)
- `assistant/gemini_agent.py` deployed

### On the PC (Windows)
- VS Code bridge running: `.\start-bridge.ps1` in `G:\Jeeves\vscode-bridge\`
- Android Studio installed (the builder writes files directly — Studio doesn't need to be open)
- Output path exists: `G:\Jeeves\projects\` (or configure a custom path)

---

## Installation

### 1. Get a Gemini API key

Go to [aistudio.google.com](https://aistudio.google.com) → **Get API Key** → copy it.

The free tier gives you **15 requests/minute** and **1,500/day** — enough for most builds.

### 2. Set the key on the Pi

```bash
sudo systemctl edit pi-assistant.service
```

Add under `[Service]`:

```ini
Environment="GEMINI_API_KEY=AIza..."
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart pi-assistant.service
```

### 3. Verify the VS Code bridge is reachable

```
!vscode ping
```

Should return `pong`. If not, start the bridge on your PC:

```powershell
cd G:\Jeeves\vscode-bridge
node server.js
```

### 4. Test the full connection

```
!android ping
```

Jeeves checks both Gemini API reachability and the VS Code bridge in one shot.

---

## Commands

| Command | Description |
|---------|-------------|
| `!android <description>` | Start an autonomous build |
| `!android stop` | Halt the current build loop |
| `!android status` | Show current phase and iteration count |
| `!android ping` | Check Gemini API + VS Code bridge |

---

## Build Phases

Each build runs through 7 phases by default. Jeeves streams a Discord message after each one:

| Phase | What gets written |
|-------|-------------------|
| 1 | Project structure + `build.gradle` / `settings.gradle` |
| 2 | Room data layer (entities, DAOs, database class) |
| 3 | Repository layer |
| 4 | Hilt dependency injection modules |
| 5 | ViewModels |
| 6 | UI — Jetpack Compose screens or XML layouts |
| 7 | Navigation graph + MainActivity entry point |

After `MAX_AUTO_ITERATIONS` (default: 10), the loop pauses and notifies you in Discord to review before continuing.

---

## Example Session

```
You:    !android build a simple expense tracker with SQLite, MVVM, Compose

Jeeves: Starting Android build: expense tracker...
        [1/7] Writing project structure...  ✓
        [2/7] Writing data layer (Room)...  ✓
        [3/7] Writing repository...         ✓
        [4/7] Writing Hilt modules...       ✓
        [5/7] Writing ViewModels...         ✓
        [6/7] Writing Compose UI...         ✓
        [7/7] Writing navigation + entry... ✓
        Build complete. 23 files written to G:\Jeeves\projects\expense-tracker\
        Open Android Studio → File → Open → select the folder.
```

---

## Configuration

In `assistant/gemini_agent.py`:

```python
GEMINI_API_KEY       = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL         = "gemini-2.0-flash"        # free tier
VSCODE_BRIDGE_URL    = "http://192.168.1.153:5055"
PC_OUTPUT_PATH       = "G:\\Jeeves\\projects"
MAX_AUTO_ITERATIONS  = 10
```

Change `VSCODE_BRIDGE_URL` if your PC is on a different IP address.  
Change `PC_OUTPUT_PATH` if you want files written elsewhere.

---

## Rate Limits

Gemini free tier: **15 requests/minute**, **1,500 requests/day**.

If a 429 rate limit is hit, Jeeves pauses, notifies you in Discord, and you can retry after 60 seconds.

For heavier use (large apps, rapid iteration), upgrade to the Gemini paid tier and switch:
```python
GEMINI_MODEL = "gemini-1.5-pro"
```

---

## Opening the Project in Android Studio

After a build completes:

1. Open Android Studio
2. **File → Open**
3. Navigate to `G:\Jeeves\projects\<app-name>\`
4. Click **OK**
5. Let Gradle sync — dependencies will download automatically
6. Run on emulator or device

The generated project targets **Android API 33+** with Kotlin, Jetpack Compose, Hilt, and Room by default.

---

## Troubleshooting

**`!android ping` shows Gemini unreachable:**
```bash
# Confirm key is set
printenv GEMINI_API_KEY

# Test directly
curl "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY"
```

**Files not appearing on PC:**
```bash
# Check bridge is running on PC
!vscode ping

# On PC — run bridge manually to see errors
cd G:\Jeeves\vscode-bridge
node server.js
```

**Build stops partway through:**
```bash
# Check for 429 rate limit or API errors
sudo journalctl -u pi-assistant -n 50 | grep android
```

**Wrong output directory:**

Pass a custom path per build:
```
!android build a todo app --path G:\Projects\todo-app
```

Or change `PC_OUTPUT_PATH` in `gemini_agent.py` permanently.

**Gradle sync fails after opening in Android Studio:**
- Check that your `build.gradle.kts` has correct AGP and Kotlin versions for your Android Studio version
- Use `!android` again with a note like "target AGP 8.3 and Kotlin 1.9" in the description
