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
