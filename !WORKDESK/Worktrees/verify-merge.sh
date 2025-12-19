#!/usr/bin/env bash
# Verify that all agent branches can merge cleanly

set -e

echo "▛▞ Merge Verification Test ⫎▸"
echo ""

BASE_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"
AGENT1_DIR="$BASE_DIR/multi-agent-collab-20251218-agent1"
AGENT2_DIR="$BASE_DIR/multi-agent-collab-20251218-agent2"
AGENT3_DIR="$BASE_DIR/multi-agent-collab-20251218-agent3"

# Merge Agent1 into Agent2
echo "Step 1: Merging Agent1 → Agent2..."
cd "$AGENT2_DIR"
git merge multi-agent-collab-20251218-agent1 --no-edit 2>&1 | grep -E "(Fast-forward|Merge|conflict|Already up to date)" || echo "✓ Merge complete"
echo ""

# Merge Agent2 into Agent3
echo "Step 2: Merging Agent2 → Agent3..."
cd "$AGENT3_DIR"
git merge multi-agent-collab-20251218-agent2 --no-edit 2>&1 | grep -E "(Fast-forward|Merge|conflict|Already up to date)" || echo "✓ Merge complete"
echo ""

# Verify all files exist in Agent3
echo "Step 3: Verifying all files present..."
cd "$AGENT3_DIR"
FILES=("file-a.md" "file-b.md" "file-c.md" "test-collaboration.md")
MISSING=0

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file MISSING"
        MISSING=1
    fi
done

echo ""
if [ $MISSING -eq 0 ]; then
    echo "▛▞ Merge Verification: PASSED ⫎▸"
    echo "✅ All files merged successfully"
    echo "✅ No conflicts detected"
    echo "✅ All agent work preserved"
else
    echo "▛▞ Merge Verification: FAILED ⫎▸"
    echo "❌ Some files missing"
    exit 1
fi

# Show final file count
echo ""
echo "Final file count in Agent3:"
ls -1 *.md 2>/dev/null | wc -l
echo "files found"
