#!/usr/bin/env bash
# Monitor all agent worktrees for changes and push for updates

WORKTREES_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"
AGENTS=("agent1-work" "agent2-work" "agent3-work" "agent4-work" "agent5-work")

echo "▛▞ Agent Monitor ⫎▸"
echo ""

for agent in "${AGENTS[@]}"; do
  WT_PATH="$WORKTREES_DIR/$agent"
  if [ -d "$WT_PATH" ]; then
    echo "Checking $agent..."
    cd "$WT_PATH"
    
    # Check for uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "  ⚠️  Uncommitted changes detected"
      git status --short | head -5
    else
      echo "  ✅ Working tree clean"
    fi
    
    # Check for unpushed commits
    LOCAL=$(git rev-list @{u}..HEAD 2>/dev/null | wc -l)
    if [ "$LOCAL" -gt 0 ]; then
      echo "  ⚠️  $LOCAL unpushed commit(s)"
    else
      echo "  ✅ All commits pushed"
    fi
    echo ""
  fi
done
