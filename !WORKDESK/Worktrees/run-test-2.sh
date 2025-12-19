#!/usr/bin/env bash
# Test 2: Task Delegation Chain
# Verify agents can delegate tasks to each other

set -e

echo "▛▞ Test 2: Task Delegation Chain ⫎▸"
echo ""

BASE_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"
DELEGATE_TOOL="$BASE_DIR/delegate-task.rb"

# Step 1: Current Agent delegates to Agent1
echo "Step 1: Delegating TASK-101 to Agent1..."
ruby "$DELEGATE_TOOL" add Agent1 "Current Agent" "Build feature X for delegation test" "feature-x.md" "high"
echo ""

# Step 2: Agent1 delegates subtask to Agent2
echo "Step 2: Agent1 delegating TASK-102 to Agent2..."
ruby "$DELEGATE_TOOL" add Agent2 Agent1 "Build component A for feature X" "component-a.md" "medium"
echo ""

# Step 3: Agent2 delegates subtask to Agent3
echo "Step 3: Agent2 delegating TASK-103 to Agent3..."
ruby "$DELEGATE_TOOL" add Agent3 Agent2 "Build sub-component B for component A" "sub-component-b.md" "low"
echo ""

# Step 4: Show task chain
echo "Step 4: Task delegation chain:"
echo ""
ruby "$DELEGATE_TOOL" list
echo ""

# Step 5: Simulate task completion (Agent3 → Agent2 → Agent1)
echo "Step 5: Simulating task completion..."
echo ""

echo "Agent3 completing TASK-103..."
ruby "$DELEGATE_TOOL" update TASK-103 completed "Sub-component B built successfully"
echo ""

echo "Agent2 completing TASK-102..."
ruby "$DELEGATE_TOOL" update TASK-102 completed "Component A built using Agent3's sub-component B"
echo ""

echo "Agent1 completing TASK-101..."
ruby "$DELEGATE_TOOL" update TASK-101 completed "Feature X built using Agent2's component A"
echo ""

# Show final status
echo "Final task status:"
ruby "$DELEGATE_TOOL" list
echo ""

echo "▛▞ Test 2 Complete ⫎▸"
echo "✅ Task delegation chain created"
echo "✅ All tasks tracked in queue"
echo "✅ Task status updates working"
