# Restoring on a fresh machine

These steps copy the backed-up agents and skills into the correct locations
for Claude Code to pick them up.

## Steps

```bash
# 1. Clone this repo somewhere convenient
git clone git@github.com:trailerkiss/claude-config.git ~/projects/claude-config
cd ~/projects/claude-config

# 2. Create the target directories if they don't exist
mkdir -p ~/.claude/agents ~/.claude/skills

# 3. Copy agent definitions
cp agents/*.md ~/.claude/agents/

# 4. Copy skill definitions (preserves subdirectory structure)
cp -r skills/* ~/.claude/skills/
```

## What you still need to configure manually

The following are **not backed up** in this repo and must be set up fresh on
each machine:

- **MCP servers** — add them via Claude Code's `/mcp` command or by editing
  `~/.claude/settings.json` directly; each machine may need different paths
- **GitHub PAT / API tokens** — stored in `~/.claude.json`; generate a new
  token for each machine and configure it via `claude config` or the
  settings UI
- **Machine-specific settings** — `settings.local.json` is excluded from
  this backup intentionally

## Keeping the backup up to date

After editing an agent or skill in `~/.claude/`:

```bash
cd ~/projects/claude-config
./sync.sh          # copies changes from ~/.claude/ into the repo
git diff           # review what changed
git add -A
git commit -m "..."
git push
```
