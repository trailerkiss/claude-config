#!/usr/bin/env bash
# sync.sh — copy FROM ~/.claude/ INTO this repo (one direction only).
#
# CANONICAL SOURCE : ~/.claude/
# MIRROR (this repo): ~/projects/claude-config/ (or wherever you cloned it)
#
# This script NEVER copies in the other direction.
# It NEVER touches ~/.claude.json or anything outside
# ~/.claude/agents/ and ~/.claude/skills/.
#
# Usage:
#   ./sync.sh
#   Review output, then: git status && git diff && git add -A && git commit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENTS_SRC="$HOME/.claude/agents"
SKILLS_SRC="$HOME/.claude/skills"
AGENTS_DST="$SCRIPT_DIR/agents"
SKILLS_DST="$SCRIPT_DIR/skills"

echo "=== claude-config sync: ~/.claude → repo ==="
echo "    Source agents : $AGENTS_SRC"
echo "    Source skills : $SKILLS_SRC"
echo "    Repo          : $SCRIPT_DIR"
echo ""

# ---------------------------------------------------------------------------
# agents/ — cp without --delete (conservative).
#
# Rationale: if you are mid-edit on an agent, a partial/broken file in
# ~/.claude/agents/ shouldn't silently propagate or delete other agents in
# the repo.  Manual review before git-add catches accidents.
# ---------------------------------------------------------------------------
echo "[agents] Copying .md files from $AGENTS_SRC/ ..."
mkdir -p "$AGENTS_DST"

# Collect .md files into an array so we can check for empty glob safely.
md_files=("$AGENTS_SRC"/*.md)
if [[ -e "${md_files[0]}" ]]; then
    cp "${md_files[@]}" "$AGENTS_DST/"
    echo "  Copied ${#md_files[@]} .md file(s) → $AGENTS_DST/"
else
    echo "  (no .md files found in $AGENTS_SRC/)"
fi
echo ""

# ---------------------------------------------------------------------------
# skills/ — rsync --delete (propagate deletions from source).
#
# Only .md files and the directories that contain them are synced.
# All other file types (JSON, binaries, etc.) are excluded even if present
# in the source — belt-and-suspenders alongside the .gitignore deny policy.
# ---------------------------------------------------------------------------
echo "[skills] Rsyncing .md files from $SKILLS_SRC/ (deletions propagated) ..."
mkdir -p "$SKILLS_DST"
rsync -a --delete \
    --include='*/'   \
    --include='*.md' \
    --exclude='*'    \
    "$SKILLS_SRC/" "$SKILLS_DST/"
echo "  Done → $SKILLS_DST/"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Sync complete. Nothing was written to ~/.claude/ ==="
echo ""
echo "Next steps:"
echo "  git -C \"$SCRIPT_DIR\" status"
echo "  git -C \"$SCRIPT_DIR\" diff"
echo "  git -C \"$SCRIPT_DIR\" add -A && git -C \"$SCRIPT_DIR\" commit -m '...'"
