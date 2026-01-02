///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ::[0xA4]::
▛//▞▞ ⟦⎊⟧ :: ⧗-25.146 // WORKFLOW :: File Analysis + Context Memory ▞▞
▛▞// Complete.Workflow :: ρ{ingest}.φ{analyze}.τ{execute} ▹
//▞⋮⋮ ⟦🔧⟧ :: [file.analysis] [conversation.memory] [intelligent.routing]

# CMD.BRIDGE Complete Workflow Documentation

## Overview

Complete intelligent file processing workflow with conversation memory for CMD.BRIDGE system.

## Features Implemented

### 1. **Intelligent File Analysis** (`file.analyzer.rb`)

Automatically analyzes dropped files and determines required actions:

**Actions:**
- **MOVE** - Relocate to different folder
- **CODEX** - Link to knowledge base
- **PROJECT** - Create project structure with support files
- **GROUP** - Group with related files
- **EDIT** - Copy to WORKDESK for editing
- **ARCHIVE** - Archive for storage
- **REFERENCE** - Add to reference library

**Analysis Process:**
1. Extract file metadata (type, size, modified time)
2. Read content sample (first 2KB)
3. Check for accompanying `.note.txt` file
4. Call LLM for intelligent analysis
5. Parse structured response
6. Execute determined actions
7. Store analysis in Redis

### 2. **Conversation Context Memory** (`conversation.context.rb`)

Redis-backed conversation memory enables "what were we talking about?" queries:

**Features:**
- Store up to 50 messages per session
- 7-day TTL for conversations
- Automatic topic extraction
- Context summarization
- Multi-session support

**Queries Recognized:**
- "What were we talking about?"
- "What was our conversation?"
- "What did I say?"
- "Remind me what..."
- "Conversation history"

### 3. **Enhanced Station Watcher**

Station now performs intelligent file analysis:

**Workflow:**
1. File dropped into `!1N.3OX/`
2. Check for `.note.txt` companion file
3. Run file analysis (calls LLM)
4. Create job with analysis metadata
5. Queue job to Redis
6. Worker executes determined actions

### 4. **Enhanced Brains.exe Worker**

Workers now handle conversation context:

**Ask Job Processing:**
1. Check if query is about context
2. If yes: Query Redis conversation history
3. If no: Call LLM provider
4. Store both user prompt and response in Redis
5. Return result

**Ingest Job Processing:**
1. Extract analysis from job metadata
2. Execute determined actions:
   - Copy to WORKDESK
   - Create project structure
   - Link to codex
   - Group files
   - etc.
3. Store actions taken in Redis

## Complete Workflow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    FILE DROP                                │
│  User drops file.md + file.note.txt into !1N.3OX/          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              STATION WATCHER (station.serve.rb)             │
│  1. Detect new file                                         │
│  2. Read .note.txt if present                               │
│  3. Call file.analyzer.rb                                   │
│     → Extract content sample                                │
│     → Build analysis prompt                                 │
│     → Call LLM: "What needs to be done?"                    │
│     → Parse response (ACTION/REASON/LOCATION/LINKS)         │
│  4. Create job with analysis metadata                       │
│  5. Push to Redis queue                                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    REDIS QUEUE                              │
│  Job stored with:                                           │
│  • file info                                                │
│  • analysis { action, reason, location, priority }          │
│  • user note                                                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              BRAINS.EXE WORKER                              │
│  1. Fetch job from queue                                    │
│  2. Validate with Imprint (if enabled)                      │
│  3. Execute based on analysis.action:                       │
│     → EDIT: Copy to !WORKDESK/                              │
│     → PROJECT: Create project structure                     │
│     → CODEX: Link to knowledge base                         │
│     → GROUP: Create file group                              │
│     → MOVE/ARCHIVE/REFERENCE: Execute action                │
│  4. Store result in Redis                                   │
│  5. Write dual receipts                                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                     EGRESS                                  │
│  • Original file stays in place                             │
│  • Work copy in !WORKDESK/ (if EDIT action)                │
│  • Project structure created (if PROJECT action)            │
│  • Receipts written (CMD.BRIDGE + Imprint)                 │
│  • Analysis stored in Redis                                 │
└─────────────────────────────────────────────────────────────┘
```

## Conversation Memory Flow

```
┌─────────────────────────────────────────────────────────────┐
│  USER: "Process this file"                                  │
│  → Stored in Redis: conversation:session_id                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  ASSISTANT: "I'll analyze and route it to WORKDESK"         │
│  → Stored in Redis: conversation:session_id                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                    (later...)
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  USER: "What were we talking about?"                        │
│  → Detected as context query                                │
│  → Query Redis conversation:session_id                      │
│  → Extract topics, summarize, format response               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  ASSISTANT: Returns conversation summary:                   │
│  "You asked about file processing. We discussed:            │
│   • File analysis workflow                                  │
│   • Routing to WORKDESK                                     │
│   Last 5 messages: [... context ...]"                       │
└─────────────────────────────────────────────────────────────┘
```

## Usage Examples

### File Drop with Note

```bash
# Drop file with analysis note
cp document.md /root/!CMD.BRIDGE/!1N.3OX/

# Add note for context
echo "This needs to be linked to the Architecture project" > /root/!CMD.BRIDGE/!1N.3OX/document.note.txt

# Station will automatically:
# 1. Analyze file + note
# 2. Determine action (likely PROJECT)
# 3. Create job
# 4. Worker will execute
```

### Manual File Analysis

```bash
cd /root/!CMD.BRIDGE/.3ox/vec3

# Analyze only (no execution)
ruby dev/ops/file.analyzer.rb /path/to/file.md

# Analyze with note
ruby dev/ops/file.analyzer.rb /path/to/file.md --note "Move to project folder"

# Analyze and execute
ruby dev/ops/file.analyzer.rb /path/to/file.md --execute
```

### Conversation Context

```bash
cd /root/!CMD.BRIDGE/.3ox/vec3

# Add message to session
ruby dev/ops/conversation.context.rb add \
  --session telegram_12345 \
  --role user \
  --message "Analyze this file for me"

# Get conversation summary
ruby dev/ops/conversation.context.rb summary --session telegram_12345

# Answer context query
ruby dev/ops/conversation.context.rb context --session telegram_12345

# List active sessions
ruby dev/ops/conversation.context.rb sessions
```

### Testing Complete Workflow

```bash
# Run end-to-end test
cd /root/!CMD.BRIDGE/.3ox
ruby test.workflow.rb
```

## System Startup (Complete)

```bash
# Terminal 1: Start Redis
redis-server

# Terminal 2: Start Station Watcher
cd /root/!CMD.BRIDGE/.3ox
ruby run.rb serve

# Terminal 3: Start Worker(s)
cd /root/!CMD.BRIDGE/.3ox
ruby run.rb worker

# Terminal 4: Test
cd /root/!CMD.BRIDGE/.3ox

# Test conversation memory
ruby run.rb ask "We are testing file analysis"
ruby run.rb ask "What were we talking about?"

# Check status
ruby run.rb status

# Drop test file
cp test.md /root/!CMD.BRIDGE/!1N.3OX/
# Watch logs in Terminal 2 and 3
```

## Telegram Integration

When connected to Telegram:

**User:** _drops file via Telegram_  
**System:** File saved to !1N.3OX/, analyzed, queued  
**Worker:** Executes analysis, routes file  
**Bot:** "File analyzed. Action: EDIT. Copied to WORKDESK."

**User:** "What were we talking about?"  
**System:** Detects context query  
**Bot:** "We discussed file processing. You dropped document.md and I routed it to WORKDESK for editing."

## File Actions in Detail

### EDIT Action
```
Original: /root/!CMD.BRIDGE/!1N.3OX/file.md (stays in place)
Copy:     /root/!CMD.BRIDGE/!WORKDESK/file.md (for editing)
```

### PROJECT Action
```
Creates:
/root/!CMD.BRIDGE/!WORKDESK/ProjectName/
  ├── file.md (original copied here)
  ├── README.md (project info)
  ├── support/ (support files)
  └── output/ (processed output)
```

### CODEX Action
```
Original: stays in place
Link:     /root/!CMD.BRIDGE/!CODEX/file.link.md
Copy:     /root/!CMD.BRIDGE/!WORKDESK/file.md
```

### GROUP Action
```
Creates:
/root/!CMD.BRIDGE/!GROUPS/group_name/
  ├── file1.md
  ├── file2.md
  └── file3.md (related files grouped)
```

## Redis Data Structures

### Conversation Context
```
Key: conversation:session_id
Type: LIST
Value: [
  { role: "user", content: "...", timestamp: "..." },
  { role: "assistant", content: "...", timestamp: "..." }
]
TTL: 7 days
```

### File Analysis
```
Key: file_analysis:file_hash
Type: HASH
Value: {
  filepath: "...",
  analysis: { action: "EDIT", reason: "...", ... },
  actions_taken: [ "Copied to WORKDESK", ... ],
  timestamp: "..."
}
TTL: 30 days
```

### Job Queue
```
Key: queue:jobs
Type: LIST
Value: [job_json, job_json, ...]
```

### Job Results
```
Key: result:job_id
Type: HASH
Value: { job_id, status, result, ... }
TTL: 7 days
```

## Key Benefits

✅ **Intelligent Routing** - LLM determines what to do with each file  
✅ **Context Memory** - System remembers conversations  
✅ **User Notes** - Add context via .note.txt files  
✅ **Obsidian Integration** - Reference Obsidian files in notes  
✅ **Work Copy** - Original stays safe, edit copy in WORKDESK  
✅ **Project Structure** - Auto-creates project folders  
✅ **Codex Linking** - Links to knowledge base  
✅ **File Grouping** - Groups related files  
✅ **Telegram Ready** - Works with Telegram bot  
✅ **Complete Audit Trail** - Dual receipts (CMD + Imprint)

## Files Created/Modified

### Created:
1. `/root/!CMD.BRIDGE/.3ox/vec3/dev/ops/file.analyzer.rb`
   - Intelligent file analysis with LLM

2. `/root/!CMD.BRIDGE/.3ox/vec3/dev/ops/conversation.context.rb`
   - Redis-backed conversation memory

3. `/root/!CMD.BRIDGE/.3ox/test.workflow.rb`
   - End-to-end workflow test script

### Modified:
4. `/root/!CMD.BRIDGE/.3ox/vec3/dev/ops/station.serve.rb`
   - Added file analysis integration
   - Added .note.txt support

5. `/root/!CMD.BRIDGE/.3ox/vec3/lib/brains.exe.rb`
   - Added conversation context handling
   - Added context query detection
   - Enhanced ingest job handler

## Testing

Run the test workflow:
```bash
cd /root/!CMD.BRIDGE/.3ox
ruby test.workflow.rb
```

This will test:
1. ✓ Redis connectivity
2. ✓ Conversation context (memory)
3. ✓ File analysis
4. ✓ File drop simulation
5. ✓ Job queue integration
6. ✓ System status

## Next Steps

1. Start all services (Redis, Station, Worker)
2. Drop test files with notes
3. Test conversation memory: "what were we talking about?"
4. Monitor receipts and analysis results
5. Integrate with Telegram bot
6. Test with Obsidian references

## Complete!

The system now provides:
- **Intelligent file routing** based on LLM analysis
- **Conversation memory** for context queries
- **User notes** for additional context
- **Obsidian integration** ready
- **Multiple action types** (EDIT, PROJECT, CODEX, GROUP, etc.)
- **Work copy management** (original preserved)
- **Complete audit trail** via receipts

All integrated with the dispatch → Redis → worker architecture and Imprint governance.

:: ∎ //▚▚▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
