# claude-skills

Claude Code skill files, backed up from this machine (`~/.claude/skills`).

## Skills

- **code-reviewer** — Comprehensive multi-pass code review with security as the top priority, then error handling, performance, code quality, testing, concurrency, and dependencies. Triggers whenever code is shared for review, audit, or feedback.
- **python-coding-standards** — Mandatory standards applied before writing or modifying any Python code, from one-off scripts to full modules.

## Syncing

This repo is maintained **manually** — make changes under `~/.claude/skills`, then commit and push:

```bash
git -C ~/.claude/skills add -A
git -C ~/.claude/skills commit -m "Update skills"
git -C ~/.claude/skills push
```

> Note: there is no `claudepush` alias on this machine. Earlier workflows referenced such an alias for syncing, but it doesn't exist here, so use the plain `git` commands above instead.
