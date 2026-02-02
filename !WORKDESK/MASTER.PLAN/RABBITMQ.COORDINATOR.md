# RabbitMQ Integration Coordinator

## Task Order

1. **TASK.01** - Dependencies (START HERE - must work first)
2. **TASK.02** - Teleprompter Publisher (needs Task 01)
3. **TASK.03** - MetaTron Consumer (needs Task 02)
4. **TASK.04** - ZENS3N Consumer (needs Task 02)
5. **TASK.05** - Redis Memory Sync (needs Task 01)

## Instructions for Agents

1. **Start with TASK.01** - Make sure it works completely
2. **Return files to:** `/root/!LAUNCHPAD/!WORKDESK/MASTER.PLAN/RABBITMQ.RETURNS/TASK.XX/`
3. **Test before moving to next task**
4. **Each agent should work on ONE task at a time**

## Return File Structure

```
RABBITMQ.RETURNS/
├── TASK.01/
│   ├── mix.exs
│   └── scripts/
├── TASK.02/
│   └── lib/services/teleprompter/server.ex
├── TASK.03/
│   └── lib/agents/metatron.ex
├── TASK.04/
│   └── lib/agents/zens3n.ex
└── TASK.05/
    ├── lib/services/agent_memory.ex
    └── updated_agents/
```

## Testing Checklist

After each task:
- [ ] Files compile without errors
- [ ] Dependencies install correctly
- [ ] Services start without crashing
- [ ] Basic functionality works

## Notes

- All tasks use copied banners from existing task files
- Return location is clearly specified in each task
- Dependencies are clearly marked
- Start with Task 01 and verify it works before proceeding
