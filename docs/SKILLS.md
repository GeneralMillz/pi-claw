# 📘 Pi Assistant Skill System

### *Modular, Extensible, Multi-Agent Skill Architecture for Jeeves*

The Pi Assistant includes a **Skill System** that allows Jeeves to dynamically load, index, and execute capabilities from a large local skill library. Skills are defined declaratively using `SKILL.md` files and automatically integrated into Jeeves' reasoning and tool-use pipeline.

---

## Skill Library Overview

Your skill library lives on the Pi at:

```
/mnt/storage/pi-assistant/skills/
```

Two sources:

**1. antigravity-awesome-skills** — A curated library of 968+ community skills, each with a `SKILL.md` file.

**2. Custom skills** — Your own skills live here:

```
/mnt/storage/pi-assistant/skills/custom/
```

Each skill is a folder:

```
<skill-name>/
    SKILL.md
    (optional) code/
    (optional) assets/
```

---

## Installing Skills

```
jeeves !skill install
```

This triggers the full skill ingestion pipeline:

1. **Discovery** — Jeeves scans `/mnt/storage/pi-assistant/skills/` for every folder containing a `SKILL.md`
2. **Parsing** — Each `SKILL.md` is parsed for name, description, tags, examples, tool definitions, natural language triggers, and constraints
3. **Indexing** — All parsed metadata is added to the Skill Index (searchable in-memory database)
4. **Registration** — Skills are registered with the internal Skill Router so they can be searched, loaded, auto-injected, and used by Claude Code
5. **Confirmation** — You'll see: `[skills] updated: Already up to date. (968 skills ready)`

---

## Skill Commands

| Command | Description |
|---------|-------------|
| `!skill install` | Scan and index all skills |
| `!skill list` | List all installed skills |
| `!skill search <query>` | Search by name, tags, description, or examples |
| `!skill load <skill-name>` | Load a specific skill |
| `!skill count` | Count installed skills |
| `!skill update` | Re-index changed skills only |
| `!skill help` | Show skill command help |

---

## How Claude Code Uses Skills

When Claude Code sends a request to Jeeves, the system prompt includes the active skills and skill index. When you ask something technical, Jeeves:

1. **Detects relevant skills** — matches your query against skill metadata
2. **Loads top-ranked skills** — injects their `SKILL.md` content into the system prompt
3. **Enhances reasoning** — Claude Code now has domain-specific instructions
4. **Executes tools or generates output** — using the skill's definitions and examples

This is called **Skill Auto-Injection**.

---

## Skill Auto-Injection

Auto-injection is what makes Jeeves feel like a multi-agent system.

When you ask:
```
Build me a docker-compose file for FastAPI + Redis
```

Jeeves:
1. Searches the skill index
2. Finds `docker-compose-generator`
3. Loads its `SKILL.md`
4. Injects it into the system prompt
5. Claude Code generates correct YAML

This gives you consistent output, domain-specific accuracy, reproducible behavior, and modular extensibility.

---

## Adding New Skills

**1. Create a folder:**
```
/mnt/storage/pi-assistant/skills/custom/<skill-name>/
```

**2. Add a `SKILL.md`:**
```md
# Skill: docker-compose-generator

## Description
Generates production-ready docker-compose.yml files.

## Tags
docker, containers, devops

## Tools
- generate_compose

## Examples
"Create a docker-compose file for Redis + FastAPI"
"Add environment variables to my compose file"
```

**3. Install:**
```
jeeves !skill install
```

---

## Updating Skills

If you modify a `SKILL.md`:
```
jeeves !skill update
```

Re-indexes only changed skills.

---

## Skill Folder Anatomy

```
my-skill/
    SKILL.md          ← required
    code/
        helper.py     ← optional
    assets/
        example.json  ← optional
```

Only `SKILL.md` is required.

---

## SKILL.md Template

```md
# Skill: <name>

## Description
Short explanation of what the skill does.

## Tags
tag1, tag2, tag3

## Tools
- tool_name_1
- tool_name_2

## Examples
"Example natural language query"
"Another example"
```

---

## Example Workflow

```
You:    jeeves !skill search docker
Jeeves: Found: docker-compose-generator, docker-cli-helper

You:    Build me a docker-compose for a FastAPI app + Redis
Jeeves: [loads docker-compose-generator skill]
        [injects SKILL.md into system prompt]
        [generates docker-compose.yml]
```

---

## Why This System Matters

| Benefit | Description |
|---------|-------------|
| **Modularity** | Add/remove skills without touching core code |
| **Extensibility** | 968+ skills ready to activate |
| **Reproducibility** | `SKILL.md` defines behavior declaratively |
| **Claude Code synergy** | Perfect for tool-use LLMs |
| **Offline capability** | Everything runs locally on the Pi |
| **Multi-agent behavior** | Each skill acts like a specialist agent |

This is the same architecture pattern used by LangChain tools, OpenAI function calling, and Anthropic tool use — but running locally, for free.
