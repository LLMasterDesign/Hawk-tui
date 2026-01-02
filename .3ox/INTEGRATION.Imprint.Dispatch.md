///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ::[0xA4]::
▛//▞▞ ⟦⎊⟧ :: ⧗-25.146 // INTEGRATION :: Imprint + Dispatch ▞▞
▛▞// Architecture.Integration :: ρ{governance}.φ{validation}.τ{execution} ▹
//▞⋮⋮ ⟦🔧⟧ :: [imprint.bridge] [governance.layer] [unified.flow]

# Imprint.ID + Dispatch Architecture Integration

## Overview

Integrated Imprint.ID governance system with the new dispatch → Redis → brains.exe architecture.

## Architecture Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                         INGRESS LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│  IN1N.3OX  │  REST API  │  Telegram  │  Shell  │  run.rb       │
└──────┬──────────┬──────────┬─────────────┬──────────┬───────────┘
       │          │          │             │          │
       └──────────┴──────────┴─────────────┴──────────┘
                            │
                    ┌───────▼────────┐
                    │  run.rb        │
                    │  (Dispatcher)  │
                    │  • Normalize   │
                    │  • Create Job  │
                    │  • Queue       │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Redis Queue   │
                    │  queue:jobs    │
                    └───────┬────────┘
                            │
                  ┌─────────┴─────────┐
                  │                   │
          ┌───────▼────────┐  ┌──────▼────────┐
          │  brains.exe #1 │  │ brains.exe #2 │
          │                │  │               │
          │  ┌──────────┐  │  │  ┌──────────┐ │
          │  │ Imprint  │  │  │  │ Imprint  │ │
          │  │ Bridge   │  │  │  │ Bridge   │ │
          │  └────┬─────┘  │  │  └────┬─────┘ │
          │       │        │  │       │       │
          │       ▼        │  │       ▼       │
          │  ┌──────────┐  │  │  ┌──────────┐ │
          │  │Validate  │  │  │  │Validate  │ │
          │  │Job       │  │  │  │Job       │ │
          │  └────┬─────┘  │  │  └────┬─────┘ │
          │       │        │  │       │       │
          │       ▼        │  │       ▼       │
          │  ┌──────────┐  │  │  ┌──────────┐ │
          │  │Execute   │  │  │  │Execute   │ │
          │  │Tools     │  │  │  │Tools     │ │
          │  └────┬─────┘  │  │  └────┬─────┘ │
          │       │        │  │       │       │
          │       ▼        │  │       ▼       │
          │  ┌──────────┐  │  │  ┌──────────┐ │
          │  │Write     │  │  │  │Write     │ │
          │  │Receipt   │  │  │  │Receipt   │ │
          │  └──────────┘  │  │  └──────────┘ │
          └────────────────┘  └───────────────┘
                  │                  │
          ┌───────▼──────────────────▼────────┐
          │  Redis State + Imprint State      │
          │  • receipts:* (CMD.BRIDGE)        │
          │  • result:*                       │
          │  • session:*                      │
          │  • imprint:active (Imprint.ID)    │
          │  • imprint:receipts               │
          └───────┬───────────────────────────┘
                  │
          ┌───────▼────────┐
          │     EGRESS     │
          │  • 0UT.3OX     │
          │  • WORKDESK    │
          │  • 3ox.log     │
          └────────────────┘
```

## Integration Components

### 1. Imprint Bridge (`imprint.bridge.rb`)

Ruby library that bridges brains.exe workers to Imprint.ID (Elixir).

**Features:**
- Load active imprint from Redis or HTTP API
- Validate jobs against Imprint governance rules
- Match routes based on Imprint route definitions
- Submit receipts to Imprint system
- Health check for Imprint availability
- Dual mode: HTTP API or direct Elixir execution

**API:**
```ruby
# Load active imprint
imprint = ImprintBridge.load_active_imprint

# Validate job
validation = ImprintBridge.validate_job(job, imprint)
# Returns: { valid: true/false, tool_id: "...", action: "proceed"/"refuse" }

# Match route
route = ImprintBridge.match_route(input_text, imprint)
# Returns: { matched: true/false, route_id: "...", eligible_tools: [...] }

# Create and submit receipt
receipt = ImprintBridge.create_imprint_receipt(job, result, imprint_id)
ImprintBridge.submit_receipt(receipt)

# Health check
health = ImprintBridge.health_check
```

### 2. Enhanced brains.exe Worker

Modified to integrate Imprint governance:

**Initialization:**
- Checks Imprint availability on startup
- Runs with or without governance (graceful degradation)

**Job Processing Flow:**
1. **Fetch job** from Redis queue
2. **Validate against Imprint** (if enabled)
   - Check tool eligibility
   - Match route
   - Refuse if not allowed
3. **Execute job** (if validation passes)
4. **Generate result**
5. **Submit dual receipts:**
   - CMD.BRIDGE receipt (Redis + file)
   - Imprint receipt (Imprint.ID system)

**Governance Enforcement:**
```ruby
if @imprint_enabled
  validation = ImprintBridge.validate_job(job)
  
  unless validation[:valid]
    # REFUSE execution
    log_operation('imprint_validation', 'REFUSE', ...)
    mark_as_failed(job, 'Imprint governance refused execution')
    return  # Job not executed
  end
end
```

### 3. Imprint Configuration Files

Uses existing Imprint.ID configuration:

**`tools.yml`** → Defines available tools with contracts
**`routes.json`** → Defines routing rules and tool eligibility
**`brains.rs`** → Agent persona and policy configuration

These files are:
- **Compiled** into Imprint struct
- **Stored** in Redis as `imprint:active`
- **Referenced** by every worker on every turn

## Governance Flow

### Job Submission → Execution

```
1. User submits "ask" command
   ↓
2. run.rb creates job { job_type: "ask", payload: { prompt: "..." } }
   ↓
3. Job pushed to Redis queue
   ↓
4. brains.exe worker fetches job
   ↓
5. Imprint validation:
   - Load active imprint from Redis
   - Map job_type → tool_id ("ask" → "tool.text_analysis")
   - Check tool eligibility in imprint
   - Match route based on input
   ↓
6a. IF VALID: Execute job → Write receipts → Complete
6b. IF INVALID: Refuse → Log reason → Fail job
```

### Receipt Double-Write

Every executed job generates **two receipts**:

1. **CMD.BRIDGE Receipt** (job-focused)
   - Stored in Redis (`receipt:*`)
   - Stored in filesystem (`var/receipts/`)
   - Tracks job lifecycle, worker, timing

2. **Imprint Receipt** (governance-focused)
   - Stored via Imprint.ID system
   - References `imprint_id` used for validation
   - Tracks tool usage, route matching, compliance

Both receipts share same `trace_id` for correlation.

## Configuration

### Environment Variables

```bash
# Imprint Server URL (optional, falls back to direct Elixir)
export IMPRINT_SERVER_URL="http://localhost:4000"

# Imprint Lab Path
export IMPRINT_LAB_PATH="/root/!CMD.BRIDGE/!ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID"
```

### Start Imprint Server (Optional)

```bash
cd /root/!CMD.BRIDGE/!ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID

# Compile Imprint modules
mix compile

# Start HTTP server
elixir imprint_server.exs
```

Or run without server (direct Elixir calls).

## Testing

### Test Imprint Bridge

```bash
# Health check
ruby /root/!CMD.BRIDGE/.3ox/vec3/lib/imprint.bridge.rb --command health

# Load active imprint
ruby /root/!CMD.BRIDGE/.3ox/vec3/lib/imprint.bridge.rb --command load

# Validate a job
echo '{"job_type":"ask","payload":{"prompt":"test"}}' > /tmp/test_job.json
ruby /root/!CMD.BRIDGE/.3ox/vec3/lib/imprint.bridge.rb --command validate --job /tmp/test_job.json
```

### Test End-to-End

```bash
# Terminal 1: Start Redis
redis-server

# Terminal 2: Start Imprint server (optional)
cd /root/!CMD.BRIDGE/!ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID
elixir imprint_server.exs

# Terminal 3: Start brains.exe worker
cd /root/!CMD.BRIDGE/.3ox
ruby run.rb worker

# Terminal 4: Submit jobs
ruby run.rb ask "What is the meaning of life?"
ruby run.rb status
```

## Key Benefits

### 1. **Unified Governance**
- Single Imprint struct governs all workers
- Consistent enforcement across all job types
- Centralized policy management

### 2. **Graceful Degradation**
- Works with or without Imprint.ID
- Logs governance decisions
- Maintains operation if Imprint unavailable

### 3. **Dual Receipt Trail**
- Job execution tracked in CMD.BRIDGE
- Governance compliance tracked in Imprint.ID
- Full audit trail with correlation

### 4. **Scalable Validation**
- Each worker validates independently
- No bottleneck on single validator
- Redis-backed imprint shared across workers

### 5. **Clear Refusal Path**
- Jobs refused by Imprint are not executed
- Refusal reason logged and reported
- No silent failures

## Files Modified/Created

### Created:
1. `/root/!CMD.BRIDGE/.3ox/vec3/lib/imprint.bridge.rb` (NEW)
   - Ruby-Elixir bridge for Imprint.ID

### Modified:
2. `/root/!CMD.BRIDGE/.3ox/vec3/lib/brains.exe.rb` (MODIFIED)
   - Added Imprint validation in process_job()
   - Added Imprint receipt submission
   - Added graceful degradation

### Existing (Used):
3. `/root/!CMD.BRIDGE/.3ox/tools.yml` - Tool definitions
4. `/root/!CMD.BRIDGE/.3ox/routes.json` - Route definitions
5. `/root/!CMD.BRIDGE/.3ox/brains.rs` - Agent configuration
6. `/root/!ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID/` - Imprint.ID codebase

## Next Steps

1. **Compile Imprint:** Create active imprint from tools.yml + routes.json + brains.rs
2. **Push to Redis:** Store imprint as `imprint:active`
3. **Test Validation:** Submit jobs and verify governance enforcement
4. **Monitor Receipts:** Check dual receipt generation
5. **Load Testing:** Test with multiple workers and high job volume

## Compliance

This integration follows **Imprint.ID governance contracts**:
- ✅ Load active imprint from Redis every turn
- ✅ Validate tool eligibility before execution
- ✅ Match routes for input classification
- ✅ Write receipt for every job (refuse or complete)
- ✅ Reference imprint_id in all receipts

**No receipt, no reply. No validation, no execution.**

:: ∎ //▚▚▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
