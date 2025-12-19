#!/usr/bin/env bash
# Cleanup script for test worktrees

set -e

echo "▛▞ Cleaning Up Test Worktrees ⫎▸"
echo ""

cd "/mnt/r/!CMD.BRIDGE"

# Remove test worktrees
WORKTREES=(
  "multi-agent-collab-20251218"
  "multi-agent-collab-20251218-agent1"
  "multi-agent-collab-20251218-agent2"
  "multi-agent-collab-20251218-agent3"
)

for wt in "${WORKTREES[@]}"; do
  WT_PATH="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/$wt"
  if [ -d "$WT_PATH" ]; then
    echo "Removing: $wt"
    git worktree remove "$WT_PATH" --force 2>&1 | grep -v "^Removing" || true
  fi
done

# Delete branches
echo ""
echo "Deleting test branches..."
for branch in "${WORKTREES[@]}"; do
  git branch -D "$branch" 2>&1 | grep -v "error:" || true
done

echo ""
echo "✓ Cleanup complete"
