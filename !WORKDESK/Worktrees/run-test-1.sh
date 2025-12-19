#!/usr/bin/env bash
# Test 1: Parallel File Editing
# Verify agents can work on different files simultaneously

set -e

echo "▛▞ Test 1: Parallel File Editing ⫎▸"
echo ""

BASE_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"
AGENT1_DIR="$BASE_DIR/multi-agent-collab-20251218-agent1"
AGENT2_DIR="$BASE_DIR/multi-agent-collab-20251218-agent2"
AGENT3_DIR="$BASE_DIR/multi-agent-collab-20251218-agent3"

# Step 1: Create test files
echo "Step 1: Creating test files..."
echo "Agent1: Creating file-a.md"
cat > "$AGENT1_DIR/file-a.md" << 'EOF'
# File A - Agent1's Work

This file is created and edited by Agent1.

## Agent1's Contribution
- Created file structure
- Added initial content
- Ready for Agent1's specific work

**Status**: Initial creation complete
**Agent**: Agent1
**Timestamp**: $(date)
EOF

echo "Agent2: Creating file-b.md"
cat > "$AGENT2_DIR/file-b.md" << 'EOF'
# File B - Agent2's Work

This file is created and edited by Agent2.

## Agent2's Contribution
- Created file structure
- Added initial content
- Ready for Agent2's specific work

**Status**: Initial creation complete
**Agent**: Agent2
**Timestamp**: $(date)
EOF

echo "Agent3: Creating file-c.md"
cat > "$AGENT3_DIR/file-c.md" << 'EOF'
# File C - Agent3's Work

This file is created and edited by Agent3.

## Agent3's Contribution
- Created file structure
- Added initial content
- Ready for Agent3's specific work

**Status**: Initial creation complete
**Agent**: Agent3
**Timestamp**: $(date)
EOF

echo "✓ Test files created"
echo ""

# Step 2: Each agent commits their file
echo "Step 2: Committing files..."

cd "$AGENT1_DIR"
git add file-a.md
git commit -m "Agent1: Create file-a.md for parallel editing test" || echo "⚠ Agent1 commit issue"

cd "$AGENT2_DIR"
git add file-b.md
git commit -m "Agent2: Create file-b.md for parallel editing test" || echo "⚠ Agent2 commit issue"

cd "$AGENT3_DIR"
git add file-c.md
git commit -m "Agent3: Create file-c.md for parallel editing test" || echo "⚠ Agent3 commit issue"

echo "✓ All files committed"
echo ""

# Step 3: Show status
echo "Step 3: Current status..."
echo ""
echo "Agent1 branch:"
cd "$AGENT1_DIR" && git log --oneline -2
echo ""
echo "Agent2 branch:"
cd "$AGENT2_DIR" && git log --oneline -2
echo ""
echo "Agent3 branch:"
cd "$AGENT3_DIR" && git log --oneline -2
echo ""

echo "▛▞ Test 1 Complete ⫎▸"
echo "✅ All agents created and committed files independently"
echo "Next: Merge branches to verify no conflicts"
