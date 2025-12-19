# Agent Task Delegation System

## Overview

The task delegation system allows agents to assign work to each other through a shared task queue. This enables:
- **Hierarchical task distribution**: One agent can coordinate multiple agents
- **Parallel work**: Agents can work on different tasks simultaneously
- **Task tracking**: All agents can see what's assigned and what's completed
- **Deep delegation**: Agents can delegate to other agents, who can delegate further

## How Deep Can It Go?

### Level 1: Direct Delegation
```
Current Agent → Agent2: "Do task X"
```

### Level 2: Chain Delegation
```
Current Agent → Agent2: "Do task X"
Agent2 → Agent3: "Help me with part Y of task X"
```

### Level 3: Multi-Agent Coordination
```
Current Agent → Agent1: "Handle frontend"
Current Agent → Agent2: "Handle backend"  
Current Agent → Agent3: "Handle testing"
Agent1 → Agent2: "I need API endpoint Z"
Agent2 → Agent3: "Test this endpoint"
```

### Level 4: Recursive Delegation
```
Current Agent → Agent1: "Build feature A"
Agent1 → Agent2: "Build component B for feature A"
Agent2 → Agent3: "Build sub-component C for component B"
Agent3 → Agent1: "I need data structure D from feature A"
```

**The depth is unlimited** - agents can delegate to each other in any pattern, as long as:
1. Tasks are tracked in `.agent-task-queue.md`
2. Agents check the queue before starting work
3. Agents update task status as they work
4. Git commits track the work flow

## Usage Examples

### Delegate a Simple Task
```bash
# From any agent worktree
ruby delegate-task.rb add Agent2 "Current Agent" "Review code changes" "src/main.rb" "high"
```

### Check Your Tasks
```bash
# See all tasks assigned to you
ruby delegate-task.rb list Agent2
```

### Update Task Status
```bash
# Mark task as in progress
ruby delegate-task.rb update TASK-001 in_progress "Starting review"

# Mark task as completed
ruby delegate-task.rb update TASK-001 completed "Review complete, all checks passed"
```

### Delegate from Within a Task
An agent can delegate subtasks while working on their assigned task:
```bash
# Agent2 is working on TASK-001, but needs help
ruby delegate-task.rb add Agent3 Agent2 "Validate test cases" "tests/spec.rb" "medium"
```

## Workflow Pattern

1. **Current Agent** creates task → commits `.agent-task-queue.md`
2. **Assigned Agent** pulls latest → sees new task → updates status to "in_progress"
3. **Assigned Agent** works on task → may delegate subtasks to other agents
4. **Assigned Agent** completes task → updates status to "completed" → commits
5. **Current Agent** pulls → sees completion → can merge/deploy

## Best Practices

1. **Check the queue first**: Before starting work, check `.agent-task-queue.md`
2. **Update status frequently**: Keep status current (pending → in_progress → completed)
3. **Commit task updates**: Git commits signal task progress to other agents
4. **Use clear descriptions**: Make task descriptions specific and actionable
5. **Set priorities**: Use priority levels to help agents prioritize work
6. **Document blockers**: If blocked, update status and add notes

## Advanced Patterns

### Task Dependencies
Create tasks that depend on other tasks:
```
TASK-001: Agent2 builds API
TASK-002: Agent3 tests API (depends on TASK-001)
```

### Task Splitting
Break large tasks into subtasks:
```
TASK-001: Build feature X (Agent1)
  → TASK-002: Build component A (Agent2, part of TASK-001)
  → TASK-003: Build component B (Agent3, part of TASK-001)
```

### Task Review Chain
Create review workflows:
```
TASK-001: Agent2 writes code
TASK-002: Agent1 reviews code (depends on TASK-001)
TASK-003: Agent3 tests reviewed code (depends on TASK-002)
```

## Limitations

- Tasks are file-based (shared through git)
- No real-time notifications (agents must pull/check)
- Manual status updates (agents must remember to update)
- Conflict resolution is manual (git merge conflicts)

## Future Enhancements

- Automated task status updates via git hooks
- Task dependency tracking
- Task priority auto-sorting
- Agent availability/load balancing
- Real-time task notifications
