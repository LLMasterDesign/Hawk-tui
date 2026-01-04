///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ::[0xA4]::
▛//▞▞ ⟦⎊⟧ :: ⧗-25.146 // INTEGRATION :: Cursor + Telegram ▞▞
▛▞// Architecture.Integration :: ρ{telegram}.φ{cursor}.τ{response} ▹
//▞⋮⋮ ⟦🔧⟧ :: [cursor.api] [telegram.bot] [job.queue] [brains.worker]

# Cursor Cloud Agent API + Telegram Integration

## Overview

Integrated Cursor's Cloud Agent API with Telegram bot using Teleprompter architecture pattern. Messages flow through Redis job queue to Cursor Brains workers.

## Architecture Flow

```
Telegram Message
    ↓
Teleprompter (bot.rb)
    ↓ Creates Job
Redis Queue (queue:jobs)
    ↓
Cursor Brains Worker (brains.cursor.rb)
    ↓ Calls Cursor API
Cursor Cloud Agent API
    ↓ Response
Outbox Event (.OPS/0ut.3ox/events)
    ↓
Redis Result (result:{job_id})
    ↓
Teleprompter (bot.rb)
    ↓
Telegram Response
```

## Components Created

### 1. Cursor API Client - Elixir (`vec3/lib/runners/cursor.api.exs`)
- **Elixir-based** client for Cursor Cloud Agent API (external signals)
- Handles HTTP calls outside localized Ruby space
- Methods: `chat_completion`, `agent_completion`, `conversation_completion`
- Health check support
- API key management from secrets file or environment

### 2. Cursor Bridge - Ruby (`vec3/lib/cursor.bridge.rb`)
- Ruby-to-Elixir bridge following Imprint pattern
- Calls Elixir module for external signals
- Falls back to direct HTTP if Elixir unavailable
- Methods: `agent_completion`, `conversation_completion`, `health_check`

### 3. Cursor API Client - Ruby Fallback (`vec3/lib/cursor.api.rb`)
- Direct HTTP client (fallback when Elixir unavailable)
- Used if Elixir bridge fails

### 2. Telegram Bot Updates (`vec3/dev/io/tg/bot.rb`)
- Modified `ask_ai()` to use job queue pattern
- Creates jobs and pushes to Redis
- Waits for results with timeout
- Fallback to ask.sh if Redis unavailable

### 4. Cursor Brains Worker (`vec3/lib/brains.cursor.rb`)
- Consumes jobs from Redis queue
- Loads conversation context
- Calls Cursor API **via Elixir bridge** (external signals)
- Writes outbox events
- Stores results in Redis
- Writes receipts

### 4. Worker Runner (`vec3/rc/run/cursor.worker.rb`)
- Simple runner script to start worker
- Handles signals gracefully

## Setup Instructions

### Step 1: Add Cursor API Key

Edit `.3ox/vec3/rc/secrets/api.keys`:

```bash
CURSOR_API_KEY=your_actual_cursor_api_key_here
```

Get your API key from: https://cursor.com/settings/api-keys

### Step 2: Install Elixir Dependencies (if using Elixir bridge)

```bash
cd /root/!CMD.BRIDGE/.3ox/vec3/lib/runners
# Install HTTPoison and Jason if needed
# Or use fallback HTTP client (cursor.api.rb)
```

**Note:** The system will fallback to direct HTTP calls if Elixir dependencies are unavailable.

### Step 3: Start Redis (if not running)

```bash
redis-server
```

### Step 4: Start Cursor Worker

```bash
cd /root/!CMD.BRIDGE/.3ox
ruby vec3/rc/run/cursor.worker.rb
```

Or run in background:

```bash
nohup ruby vec3/rc/run/cursor.worker.rb > /tmp/cursor.worker.log 2>&1 &
```

### Step 5: Start Telegram Bot

```bash
cd /root/!CMD.BRIDGE/.3ox
ruby vec3/dev/io/tg/bot.rb
```

## Testing

### Test Cursor API Directly

```bash
ruby vec3/lib/cursor.api.rb health
ruby vec3/lib/cursor.api.rb test -p "Hello, how are you?"
```

### Test Worker

```bash
# Terminal 1: Start worker
ruby vec3/rc/run/cursor.worker.rb

# Terminal 2: Push test job to queue
redis-cli lpush queue:jobs '{"job_id":"test123","job_type":"cursor_ask","trace_id":"abc","base_id":"CMD.BRIDGE","station_id":"GENERAL","thread_id":"test_thread","chat_id":"123","topic_thread_id":null,"payload":{"prompt":"Hello","username":"test","user_id":123},"created_at":"2025-01-03T00:00:00Z"}'
```

### Test Telegram Bot

Send a message to your Telegram bot. It should:
1. Create job and push to queue
2. Worker picks up job
3. Calls Cursor API
4. Returns response to Telegram

## Configuration

### Environment Variables

- `CURSOR_API_KEY` - Cursor API key (from secrets file)
- `REDIS_HOST` - Redis host (default: localhost)
- `REDIS_PORT` - Redis port (default: 6379)

### Worker Options

```bash
ruby vec3/lib/brains.cursor.rb --base-id CMD.BRIDGE --station-id GENERAL
```

## File Structure

```
.3ox/
├── vec3/
│   ├── lib/
│   │   ├── cursor.api.rb          # Cursor API client (HTTP fallback)
│   │   ├── cursor.bridge.rb       # Ruby-to-Elixir bridge
│   │   ├── brains.cursor.rb       # Cursor worker
│   │   └── runners/
│   │       └── cursor.api.exs     # Elixir Cursor API client (external signals)
│   ├── rc/
│   │   └── run/
│   │       └── cursor.worker.rb   # Worker runner
│   ├── dev/
│   │   └── io/
│   │       └── tg/
│   │           └── bot.rb          # Updated Telegram bot
│   └── rc/
│       └── secrets/
│           └── api.keys            # API keys (add CURSOR_API_KEY)
└── .OPS/
    └── 0ut.3ox/
        └── events/                 # Outbox events written here
```

## Troubleshooting

### Worker won't start
- Check CURSOR_API_KEY is set in api.keys
- Check Redis is running: `redis-cli ping`
- Check logs in `.3ox/vec3/var/logs/`

### Jobs not processing
- Check worker is running: `ps aux | grep cursor.worker`
- Check queue depth: `redis-cli llen queue:jobs`
- Check Redis connection in worker logs

### API errors
- Verify API key is correct
- Check API key has proper permissions
- Test API directly: `ruby vec3/lib/cursor.api.rb health`

### Telegram bot not responding
- Check bot is running
- Check Redis is available
- Check worker is processing jobs
- Check bot logs for errors

## Next Steps

1. ✅ Add CURSOR_API_KEY to api.keys
2. ✅ Start Redis
3. ✅ Start Cursor worker
4. ✅ Start Telegram bot
5. ✅ Test by sending message to bot

## Architecture Compliance

This integration follows the Teleprompter architecture:
- ✅ Teleprompter (bot.rb) routes messages
- ✅ Jobs pushed to Redis queue
- ✅ Brains workers consume jobs
- ✅ **External signals handled via Elixir** (cursor.api.exs)
- ✅ Ruby-to-Elixir bridge for external communications
- ✅ Outbox events written to disk
- ✅ Results stored in Redis
- ✅ Conversation context maintained
- ✅ Receipts written for audit

**Key Design Decision:**
- External signals (Cursor API calls) are handled by Elixir module
- Ruby code stays localized to Base
- Bridge pattern allows graceful fallback to direct HTTP if Elixir unavailable

:: ∎ //▚▚▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
