# claude-config

Backup of my Claude Code customisations — specifically the authored markdown
files inside `~/.claude/agents/` and `~/.claude/skills/`.

## What lives here

| Directory | Source | Contents |
|---|---|---|
| `agents/` | `~/.claude/agents/` | Custom sub-agent definitions (`.md` files) |
| `skills/` | `~/.claude/skills/` | Custom skill definitions and their reference docs |

## What does NOT live here

**Secrets are never backed up in this repo.** Specifically:

- `~/.claude.json` — contains GitHub PAT and other tokens; lives *outside*
  `~/.claude/` and is never touched by `sync.sh`
- `settings.json` / `settings.local.json` — machine-specific config that can
  contain API keys and MCP credentials
- Any `.json` file — blocked by `.gitignore` at the pattern level
- MCP server configuration — machine-specific, must be reconfigured manually
  on each machine

The `.gitignore` uses a **deny-by-default** policy: all files are blocked
except explicitly allowed types (`.md`, `.sh`).

## Canonical source vs this backup

`~/.claude/` is the **canonical source**. This repo is the **mirror**.

- Edit agents and skills in `~/.claude/` directly (that's where Claude Code
  reads them)
- Run `./sync.sh` to push those changes into this repo
- Commit and push to save a snapshot
- `sync.sh` never copies in the other direction

See `INSTALL.md` for how to restore on a new machine.
