# 📘 Skill System

### *Modular, Extensible, Multi-Library Skill Architecture for Jeeves*

The skill system allows Jeeves to dynamically score, select, and inject skill content from multiple libraries into every coding task. Skills are defined as `SKILL.md` files and automatically matched to project types during `!task` planning.

---

## Skill Library Credit

The primary community skill library is sourced from:

> **[antigravity-awesome-skills](https://github.com/sickn33/antigravity-awesome-skills)** by [@sickn33](https://github.com/sickn33)  
> 968+ curated skills for Claude Code and AI assistants.  
> All credit for the community library goes to the original author and contributors.  
> Please ⭐ star the original repo if you find it useful.

Custom skills you create live in `/mnt/storage/pi-assistant/skills/custom/` and are yours entirely.

---

## Skill Library Layout

```
/mnt/storage/pi-assistant/skills/
├── antigravity-awesome-skills/
│   └── skills/                  ← 978 community skills (PRIMARY)
├── claude-skills/               ← alirezarezvani/claude-skills
├── claude-scientific-skills/
│   └── scientific-skills/       ← K-Dense-AI/claude-scientific-skills
├── superpowers/
│   └── skills/                  ← 77.8k⭐ TDD methodology
├── ui_ux_pro_max_skill/
│   └── skills/                  ← 50+ UI styles, 97 palettes
└── custom/                      ← your own skills
```

Each skill is a folder containing a `SKILL.md`:

```
<skill-name>/
    SKILL.md         ← required
    code/            ← optional helpers
    assets/          ← optional examples
```

---

## Two Skill Subsystems

Jeeves has two separate skill tools that serve different purposes:

| Tool | File | Purpose |
|------|------|---------| 
| `skills_manager.py` | `tools/skills_manager.py` | Discord commands (`!skill *`) — uses `skills_index.json` |
| `skill_injector.py` | `tools/skill_injector.py` | Coding pipeline only — scans filesystem, injects relevant SKILL.md into SPEC.md |

**`skill_injector.py`** runs automatically during every `!task` — you never call it directly. **`skills_manager.py`** is for browsing and managing the library from Discord.

---

## How Skills Are Injected

When you run `!task build a tetris clone in pygame`, Jeeves:

1. **Detects project type:** `pygame_game`
2. **Scores all skills:** keyword overlap between project type keywords and skill folder names/descriptions
3. **Presents candidates:** if ≥5 found → interactive Discord menu; if <5 → auto-inject top results
4. **Builds SPEC.md:** appends selected skill content verbatim under `## Injected Skills`
5. **Continue reads SPEC.md:** 14B model sees skill constraints and best practices before writing any code

### Interactive Selection

When 5 or more candidate skills are found, Jeeves sends a numbered menu to Discord:

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

**Reply formats:**

| Reply | Effect |
|-------|--------|
| `"1,3"` | Use skills 1 and 3 |
| `"1 3 5"` | Use skills 1, 3, and 5 (space-separated also works) |
| `"all"` | Use all candidates |
| Enter / `"auto"` | Auto-select top-N |
| (no reply, 60s) | Timeout → auto-select top-3 and continue |

### Early Preview

Before the interactive menu, Jeeves sends a quick preview to Discord:

```
⚙️ Agent: Continue (Qwen 14B) | Planning...
📘 Skills: pygame-2d-games, game-development, python-patterns
```

This comes from `get_skill_summary()` and shows the top candidates before blocking for user input.

---

## Keyword Scoring

Skills are scored by matching project type keywords against skill folder names and SKILL.md descriptions. Using **specific** folder names prevents false positives.

```python
# ✅ Correct — matches specific skill folders
"pygame_game": ["pygame", "2d-games", "game-development", "platformer", "arcade", "roguelike"]

# ❌ Wrong — "game" matches three.js demos, "animation" matches anime.js
"pygame_game": ["game", "animation", "python"]
```

Current keyword sets by project type:

| Type | Scoring keywords |
|------|-----------------|
| `pygame_game` | pygame, 2d-games, game-development, platformer, arcade, roguelike, shooter, zelda, dungeon |
| `web_app` | flask, fastapi, web, api, rest, html, django, crud, routing |
| `cli_tool` | cli, command-line, argparse, terminal, utility, script |
| `discord_bot` | discord, bot, slash-command, cog, intents |
| `data_science` | data, pandas, numpy, analysis, visualization, pytorch, scikit, polars, dask, ml |
| `general_python` | python, oop, patterns, packaging, testing |

---

## Discord Skill Commands

| Command | Description |
|---------|-------------|
| `!skill install` | Scan and index all skills from all libraries |
| `!skill list` | List all installed skills |
| `!skill search <query>` | Search by name, tags, description, or examples |
| `!skill load <name>` | Load and display a specific skill |
| `!skill count` | Count installed skills across all libraries |
| `!skill update` | Re-index changed skills only |
| `!skill help` | Show skill command help |

---

## Installing Skills

```
jeeves !skill install
```

This triggers the full skill ingestion pipeline:

1. **Discovery** — scan all skill roots for folders containing `SKILL.md`
2. **Parsing** — extract name, description, tags, examples, tool definitions, triggers
3. **Indexing** — add all metadata to the Skill Index (searchable in-memory database)
4. **Registration** — register with the Skill Router for search and auto-injection
5. **Confirmation** — `[skills] updated: Already up to date. (978 skills ready)`

---

## Adding Your Own Skills

**1. Create a folder:**

```bash
mkdir -p /mnt/storage/pi-assistant/skills/custom/my-skill
```

**2. Add a `SKILL.md`:**

```markdown
# Skill: my-skill

## Description
What this skill does and when it's useful.

## Tags
tag1, tag2, tag3

## Tools
- tool_name_1

## Examples
"Example task that would trigger this skill"
"Another example"
```

**3. Index it:**

```
jeeves !skill install
```

Your skill is now available for search, manual loading, and automatic injection when its keywords match a `!task`.

---

## SKILL.md Template

```markdown
# Skill: <name>

## Description
Short explanation of what the skill does.

## Tags
tag1, tag2, tag3

## Tools
- tool_name_1
- tool_name_2

## Examples
"Example natural language query that would use this skill"
"Another example"

## Constraints
- Any hard rules Continue must follow when using this skill
- E.g. "Never use external APIs, only stdlib"
```

---

## Updating Skills

After modifying a `SKILL.md`:

```
jeeves !skill update
```

Re-indexes only changed skills (faster than full install).

---

## Cloning Additional Libraries

To add the libraries currently in use:

```bash
cd /mnt/storage/pi-assistant/skills

# Community skills (already included via install)
git clone https://github.com/sickn33/antigravity-awesome-skills

# Additional libraries
git clone https://github.com/alirezarezvani/claude-skills
git clone https://github.com/K-Dense-AI/claude-scientific-skills
git clone https://github.com/IncomeStreamSurfer/superpowers
git clone https://github.com/codyde/ui_ux_pro_max_skill
```

Then run `jeeves !skill install` to index the new additions.

---

## Skill Injector Configuration

Key constants in `tools/skill_injector.py`:

```python
# Primary library
SKILLS_ROOT = Path("/mnt/storage/pi-assistant/skills/antigravity-awesome-skills/skills")

# Additional libraries
_SKILLS_EXTRA = [
    Path("/mnt/storage/pi-assistant/skills/claude-skills"),
    Path("/mnt/storage/pi-assistant/skills/claude-scientific-skills/scientific-skills"),
    Path("/mnt/storage/pi-assistant/skills/superpowers/skills"),
    Path("/mnt/storage/pi-assistant/skills/ui_ux_pro_max_skill/skills"),
    Path("/mnt/storage/pi-assistant/skills/custom"),
]

# Interactive selection threshold
INTERACTIVE_THRESHOLD = 5   # ≥ this many candidates → show Discord menu
INTERACTION_TIMEOUT   = 60  # seconds before auto-fallback
```

To add a new library, append its path to `_SKILLS_EXTRA` and restart the service.

---

## Why This System Matters

| Benefit | Description |
|---------|-------------|
| **Modularity** | Add/remove skill libraries without touching core code |
| **Extensibility** | 978+ community skills + multiple additional libraries |
| **User control** | Interactive Discord menu for important projects |
| **Reproducibility** | SKILL.md defines behavior declaratively |
| **Offline capability** | Everything runs locally on the Pi |
| **Quality output** | Domain-specific rules injected before Continue writes a single line |

---

## Discovery Layer vs. Skill Injection

**Discovery** is a separate, non-invasive subsystem for indexing and displaying arbitrary repos in the dashboard. It has **zero impact** on the skill injection pipeline.

| Aspect | Skill Injector | Discovery |
|--------|---|---|
| **Scope** | Only `/skills/` subdirs containing `SKILL.md` | Any repo in `/skills/` or `/tools/` |
| **Scan depth** | Recursively searches subdirs for `SKILL.md` | Top-level dirs only |
| **Purpose** | Extract skill content → inject into SPEC.md | Index repos for dashboard display |
| **Triggers on** | Every `!task` command | Systemd timer (5min) + manual refresh |
| **Affects** | Continue/Cursor code generation | DiscoveryView.js table only |
| **Data flow** | Injected text → SPEC.md → LLM → code | Metadata → index.json → HTTP API → dashboard |
| **Can fail?** | If ≥5 candidates, awaits Discord reply | Never blocks; graceful degradation |

**Key guarantee:** Disabling or removing the entire Discovery subsystem has **zero effect** on skill injection. The two systems are orthogonal.

### When to Use Which

- **Skill Injector** — if you want your coding tasks to automatically include best-practices constraints from specific folders
- **Discovery** — if you want to browse and monitor all repos in your skill/tool library from the dashboard

Most users will keep both enabled. Discovery is optional; skill injection is core.

---

## Attribution

Primary community library: **[antigravity-awesome-skills](https://github.com/sickn33/antigravity-awesome-skills)** by [@sickn33](https://github.com/sickn33)

Please ⭐ star the original repo if you find it useful.
