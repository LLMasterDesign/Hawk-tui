# CMD.BRIDGE

**Intelligent dispatch and workflow automation system with LLM-powered governance**

A scalable, Redis-backed job processing system with intelligent file analysis, conversation memory, and governance enforcement via Imprint.ID.

## 🎯 What It Does

- **Intelligent File Processing**: Drop files, get LLM-powered analysis and smart routing
- **Conversation Memory**: Redis-backed context that remembers "what were we talking about?"
- **Unified Dispatch**: All ingress points → Redis queue → worker execution
- **Governance Layer**: Imprint.ID validates every job before execution
- **Telegram Integration**: Bot interface for file drops and queries
- **Scalable Workers**: Multiple brains.exe workers process jobs in parallel

## 🏗️ Architecture

```
Ingress → run.rb (Dispatcher) → Redis Queue → brains.exe (Workers) → Egress
                                      ↓
                              Imprint Validation
                              Conversation Context
                              Receipt Generation
```

### Key Components

- **`run.rb`** - Thin dispatcher, normalizes input and queues jobs
- **`brains.exe.rb`** - Worker process that executes jobs
- **`station.serve.rb`** - File watcher that monitors drop zones
- **`imprint.bridge.rb`** - Governance validation layer
- **`conversation.context.rb`** - Redis-backed conversation memory
- **`file.analyzer.rb`** - LLM-powered file analysis

## 🚀 Quick Start

### Prerequisites

- Ruby 2.7+
- Redis
- Elixir 1.9+ (for Imprint.ID, optional)
- LLM API key (OpenAI, Claude, or Ollama)

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/CMD.BRIDGE.git
cd CMD.BRIDGE

# Install dependencies
cd .3ox/vec3
bundle install  # or gem install redis

# Configure API keys
cp .3ox/vec3/rc/secrets/api.keys.example .3ox/vec3/rc/secrets/api.keys
# Edit api.keys and add your LLM API key

# Start Redis
redis-server
```

### Basic Usage

```bash
cd .3ox

# Start file watcher (monitors !1N.3OX/)
ruby run.rb serve

# Start worker (in another terminal)
ruby run.rb worker

# Test the system
ruby run.rb ask "Hello, how are you?"
ruby run.rb status

# Drop a file for analysis
cp myfile.txt /path/to/!1N.3OX/
# Worker will automatically analyze and route it
```

## 📖 Features

### 1. Intelligent File Analysis

Files dropped into `!1N.3OX/` are automatically analyzed by LLM:

```bash
# Drop file with optional note
cp document.md !1N.3OX/
echo "This needs project structure" > !1N.3OX/document.note.txt
```

**Actions automatically determined:**
- **EDIT** - Copy to WORKDESK for editing
- **PROJECT** - Create full project structure
- **CODEX** - Link to knowledge base
- **GROUP** - Group with related files
- **MOVE/ARCHIVE/REFERENCE** - Smart routing

### 2. Conversation Memory

System remembers conversations in Redis:

```bash
# Talk to the system
ruby run.rb ask "Process this file for me"
ruby run.rb ask "Create a project structure"

# Later, ask about context
ruby run.rb ask "What were we talking about?"
# System retrieves conversation history from Redis
```

### 3. Imprint Governance (Optional)

Integrate with Imprint.ID for strict governance:

```elixir
# Compile and activate imprint
cd !ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID
mix compile
elixir imprint_server.exs
```

Every job validated against active Imprint before execution.

### 4. Multiple Workers

Scale horizontally with multiple workers:

```bash
# Terminal 1
ruby run.rb worker

# Terminal 2
ruby run.rb worker

# Terminal 3
ruby run.rb worker

# All pulling from same Redis queue
```

## 📂 Project Structure

```
.3ox/                           # Core system
├── vec3/                       # Vec3 codebase
│   ├── lib/
│   │   ├── brains.exe.rb       # Worker process
│   │   ├── imprint.bridge.rb   # Governance bridge
│   │   ├── job_schema.rb       # Job structure
│   │   └── runners/
│   │       └── run.rb          # Main dispatcher
│   ├── dev/
│   │   ├── ops/
│   │   │   ├── station.serve.rb        # File watcher
│   │   │   ├── conversation.context.rb # Conversation memory
│   │   │   ├── file.analyzer.rb        # File analysis
│   │   │   ├── cache/redis.rb          # Redis client
│   │   │   └── lib/helpers.rb          # Helper functions
│   │   └── providers/
│   │       └── ask.sh          # LLM provider bridge
│   ├── bin/                    # Executables
│   └── rc/                     # Configuration
│       ├── secrets/            # API keys (not in git)
│       └── personas/           # Agent configs
├── tools.yml                   # Tool definitions
├── routes.json                 # Route definitions
├── brains.rs                   # Agent configuration
└── BUILD.*.md                  # Build documentation

!1N.3OX/                        # File drop zone
!WORKDESK/                      # Work area
!0UT.3OX/                       # Output folder
```

## 🔧 Configuration

### API Keys

```bash
# .3ox/vec3/rc/secrets/api.keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OLLAMA_HOST=http://localhost:11434
```

### Tools and Routes

Edit `.3ox/tools.yml` and `.3ox/routes.json` to customize available tools and routing logic.

### Agent Persona

Configure agent behavior in `.3ox/brains.rs`.

## 📊 Monitoring

```bash
# System status
ruby run.rb status

# Shows:
# - Redis health
# - Queue depth (pending/processing)
# - Active workers
# - Jobs processed/failed
```

## 🧪 Testing

```bash
# Run end-to-end test
ruby test.workflow.rb

# Tests:
# - Redis connectivity
# - Conversation memory
# - File analysis
# - Job queue
# - System status
```

## 📚 Documentation

- `BUILD.Dispatch.Refactor.md` - Dispatch architecture
- `INTEGRATION.Imprint.Dispatch.md` - Imprint governance integration
- `WORKFLOW.Complete.md` - Complete workflow documentation

## 🔐 Security

- API keys stored in `.3ox/vec3/rc/secrets/` (gitignored)
- Receipt HMAC signing with secret key
- Imprint governance validates all jobs
- Redis password protection (configure in redis.toml)

## 🤝 Contributing

This is a personal workspace system. Fork and adapt to your needs!

## 📝 License

Part of the ZENS3N/3OX system.

## 🎯 Key Concepts

### Jobs
Standardized units of work with type, payload, status, and metadata.

### Receipts
Every operation generates a receipt for audit trail.

### Imprint
Active governance contract that validates tools and routes.

### Station
File watcher that monitors drop zones and creates jobs.

### Brain Workers
Processes that pull jobs from queue, validate, and execute.

## 🔗 Related Projects

- **Imprint.ID** - Governance and validation system (Elixir)
- **Vec3** - Core runtime and utilities (Ruby)
- **3OX System** - Umbrella project for agent infrastructure

---

**Built with:** Ruby, Redis, Elixir, LLM APIs  
**Architecture:** Dispatch → Queue → Workers → Governance  
**Status:** Production-ready, actively developed
