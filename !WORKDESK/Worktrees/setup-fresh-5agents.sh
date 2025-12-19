#!/usr/bin/env bash
# Fresh setup with main monitoring branch + 5 agent worktrees

set -e

echo "▛▞ Fresh 5-Agent Setup ⫎▸"
echo ""

cd "/mnt/r/!CMD.BRIDGE"
BASE_BRANCH="main-monitor"
WORKTREES_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"

# Step 1: Create main monitoring branch
echo "Step 1: Creating main monitoring branch..."
git checkout -b "$BASE_BRANCH" main 2>/dev/null || git checkout "$BASE_BRANCH"
echo "✓ Main monitoring branch: $BASE_BRANCH"
echo ""

# Step 2: Create 5 agent worktrees
echo "Step 2: Creating 5 agent worktrees..."
echo ""

AGENTS=("Agent1" "Agent2" "Agent3" "Agent4" "Agent5")
BRANCHES=("agent1-work" "agent2-work" "agent3-work" "agent4-work" "agent5-work")

for i in "${!AGENTS[@]}"; do
  AGENT="${AGENTS[$i]}"
  BRANCH="${BRANCHES[$i]}"
  WT_PATH="$WORKTREES_DIR/$BRANCH"
  
  echo "Creating $AGENT ($BRANCH)..."
  
  # Create branch
  git branch "$BRANCH" "$BASE_BRANCH" 2>/dev/null || true
  
  # Create worktree
  if [ ! -d "$WT_PATH" ]; then
    git worktree add "$WT_PATH" "$BRANCH"
    
    # Setup .3ox for agent
    cd "$WT_PATH"
    if [ ! -d ".3ox" ]; then
      SETUP_SCRIPT="/mnt/r/!CMD.BRIDGE/OBSIDIAN.BASE/ZENS3N/3OX.Ai/3OX.BUILDER/3OX.BUILD/setup-3ox.rb"
      if [ -f "$SETUP_SCRIPT" ]; then
        ruby "$SETUP_SCRIPT" . "$AGENT" Sentinel 2>&1 | grep -E "(✓|created)" || true
      fi
    fi
    
    # Create agent metadata
    cat > ".worktree.meta" << EOF
{
  "agent": "$AGENT",
  "branch": "$BRANCH",
  "base_branch": "$BASE_BRANCH",
  "created": "$(date -Iseconds)",
  "purpose": "Multi-agent collaboration workspace"
}
EOF
    
    echo "✓ $AGENT ready at: $WT_PATH"
  else
    echo "⚠ $AGENT worktree already exists"
  fi
  echo ""
done

# Step 3: Create monitoring script
echo "Step 3: Creating monitoring script..."
cat > "$WORKTREES_DIR/monitor-agents.sh" << 'MONITOR'
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
MONITOR
chmod +x "$WORKTREES_DIR/monitor-agents.sh"
echo "✓ Monitor script created"
echo ""

# Step 4: Create README
cat > "$WORKTREES_DIR/README.md" << 'README'
# 5-Agent Worktree Setup

## Structure

- **Main Branch**: `main-monitor` - Monitoring and coordination branch
- **5 Agent Worktrees**: Each agent has their own branch and worktree

## Agent Worktrees

1. **Agent1** → `agent1-work` branch
2. **Agent2** → `agent2-work` branch  
3. **Agent3** → `agent3-work` branch
4. **Agent4** → `agent4-work` branch
5. **Agent5** → `agent5-work` branch

## Usage

### Monitor All Agents
```bash
./monitor-agents.sh
```

### Open Agent Worktree in Cursor
Open the worktree directory in Cursor:
- `/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/agent1-work`
- `/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/agent2-work`
- etc.

### Tell Agents
When opening multiple agents, tell each:
> "I have 5 agents open. Use LIGHTWEIGHT mode."

## Workflow

1. **Main Monitor** watches all agent branches
2. **Agents** work in their own worktrees
3. **Monitor** pushes for updates when needed
4. **Agents** can merge each other's work as needed

## Best Practices

- Check monitor script regularly
- Agents should commit frequently
- Use task delegation for coordination
- Merge strategically to avoid conflicts
README

echo "✓ README created"
echo ""

echo "▛▞ Setup Complete ⫎▸"
echo ""
echo "Main monitoring branch: $BASE_BRANCH"
echo "5 agent worktrees created"
echo ""
echo "Next steps:"
echo "  1. Open 5 Cursor windows (one per agent worktree)"
echo "  2. Tell each agent: 'I have 5 agents open. Use LIGHTWEIGHT mode.'"
echo "  3. Run: ./monitor-agents.sh to check status"
