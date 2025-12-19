# Multi-Agent Collaboration Test Guide

## Setup Summary

**Base Branch:** `multi-agent-collab-20251218` (created from `worktree-final`)

**Agent Worktrees:**
1. **Agent1**: `/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/multi-agent-collab-20251218-agent1`
   - Branch: `multi-agent-collab-20251218-agent1`
   
2. **Agent2**: `/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/multi-agent-collab-20251218-agent2`
   - Branch: `multi-agent-collab-20251218-agent2`
   
3. **Agent3**: `/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees/multi-agent-collab-20251218-agent3`
   - Branch: `multi-agent-collab-20251218-agent3`

## Workflow for Single File Collaboration

### Option 1: Sequential Workflow (Recommended for Testing)
1. **Agent1** works on the file, commits to `multi-agent-collab-20251218-agent1`
2. **Agent2** merges Agent1's branch, works on the file, commits to `multi-agent-collab-20251218-agent2`
3. **Agent3** merges Agent2's branch, works on the file, commits to `multi-agent-collab-20251218-agent3`
4. Final merge back to base branch

### Option 2: Coordinated Parallel Workflow
1. All agents pull latest from base branch before starting
2. Each agent works on different sections/tasks in the file
3. Agents merge sequentially, resolving conflicts as needed
4. Final merge to base branch

## Commands for Each Agent

### Before Starting Work:
```bash
# Pull latest from base branch
git fetch origin
git merge origin/multi-agent-collab-20251218
```

### After Completing Task:
```bash
# Commit changes
git add <target-file>
git commit -m "Agent<X>: <task description>"

# Push to remote (if needed)
git push origin <branch-name>
```

### To Merge Another Agent's Work:
```bash
# Merge Agent1's work into Agent2's branch
git merge multi-agent-collab-20251218-agent1

# Resolve conflicts if any, then commit
git commit -m "Merge Agent1 changes"
```

## Testing Checklist

- [ ] All 3 agents can read the target file
- [ ] Agent1 commits changes successfully
- [ ] Agent2 can merge Agent1's changes
- [ ] Agent2 commits additional changes successfully
- [ ] Agent3 can merge Agent2's changes
- [ ] Agent3 commits final changes successfully
- [ ] All changes are visible in final merged branch
- [ ] No data loss or conflicts

## Notes

- Each agent has its own `.3ox/` configuration
- Agents should use LIGHTWEIGHT mode when multiple agents are active
- All agents work on branches derived from the same base commit
- Final merge should be done carefully to preserve all changes
