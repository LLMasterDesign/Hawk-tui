///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ::[0xA4]::
▛//▞▞ ⟦⎊⟧ :: ⧗-25.146 // SOLVED :: Cursor API Endpoint ▞▞
▛▞// API.Research :: ρ{endpoint}.φ{verify}.τ{solved} ▹

# Cursor Cloud Agent API - SOLVED ✅

## Correct Endpoints

**Base URL:** `https://api.cursor.com/v0` (not `/v1`)

**Key Endpoints:**
- `GET /v0/me` - Get API key info ✅
- `GET /v0/models` - List available models ✅
- `POST /v0/agents` - Launch a new agent ✅
- `GET /v0/agents/{id}` - Get agent status

## Request Format

**Launch Agent:**
```json
POST /v0/agents
{
  "prompt": {
    "text": "Your prompt text here"
  },
  "model": "gpt-5.2"  // Optional
}
```

**Response:**
```json
{
  "id": "bc-4188206a-435a-44a1-9ede-66e7790d500e",
  "status": "CREATING",
  "source": {
    "repository": "https://github.com/...",
    "ref": "master"
  },
  "target": {
    "branchName": "cursor/...",
    "url": "https://cursor.com/agents?id=..."
  },
  "name": "Agent name",
  "createdAt": "2026-01-04T01:59:12.495Z"
}
```

## Important Notes

1. **Asynchronous API:** Agents run in background, don't return immediate results
2. **Prompt Format:** Must be object `{"text": "..."}` not string
3. **Agent Status:** Poll `/v0/agents/{id}` to check status
4. **Webhooks:** May need webhook setup for results (check docs)

## Updated Code

✅ Updated `cursor.api.rb` - uses `/v0/agents` endpoint  
✅ Updated `cursor.api.exs` - Elixir bridge uses correct endpoint  
✅ Health check works via `/v0/me`  
✅ Agent launch tested and working

## Next Steps for Telegram Integration

Since Cursor API is asynchronous:
1. Launch agent when Telegram message received
2. Return agent ID and status URL to user
3. Poll agent status or set up webhooks for results
4. Send results back to Telegram when agent completes

Or use alternative approach:
- Use Cursor CLI if available for synchronous operations
- Check if there's a synchronous chat endpoint (not documented)

:: ∎ //▚▚▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
