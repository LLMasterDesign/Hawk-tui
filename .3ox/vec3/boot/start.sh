#!/bin/bash
# start.sh :: PHENO vec3 Framework Startup Script

set -e

VEC3_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_NAME="PHENO vec3 Startup"

echo "▛//▞▞ ⟦⎊⟧ :: ⧗-25.125 // $SCRIPT_NAME ▞▞"
echo ""

# Check if installed
if [ ! -f "$VEC3_ROOT/var/health/status.json" ]; then
    echo "✗ System not installed. Run: ./boot/install.sh"
    exit 1
fi

# Check health
HEALTH_STATUS=$(cat "$VEC3_ROOT/var/health/status.json" | grep -o '"status": "[^"]*"' | cut -d'"' -f4)

if [ "$HEALTH_STATUS" != "healthy" ]; then
    echo "✗ System health check failed: $HEALTH_STATUS"
    exit 1
fi

echo "✓ System health: $HEALTH_STATUS"

# Validate manifest integrity
echo ""
echo "Validating manifest integrity..."

MANIFEST_FILE="$VEC3_ROOT/../../manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "✗ Manifest file missing: $MANIFEST_FILE"
    exit 1
fi

# Check core law hash
CORE_LAW_FILE="$VEC3_ROOT/rc/core/core.law.z3n"
if [ -f "$CORE_LAW_FILE" ]; then
    COMPUTED_HASH=$(sha256sum "$CORE_LAW_FILE" | cut -d' ' -f1)
    EXPECTED_HASH=$(cat "$MANIFEST_FILE" | grep -o '"core_law_sha256": "[^"]*"' | cut -d'"' -f4)
    if [ "$COMPUTED_HASH" != "$EXPECTED_HASH" ] && [ "$EXPECTED_HASH" != "pending" ]; then
        echo "✗ Core law integrity check failed"
        echo "  Expected: $EXPECTED_HASH"
        echo "  Computed: $COMPUTED_HASH"
        exit 1
    fi
    echo "✓ Core law integrity verified"
else
    echo "✗ Core law file missing: $CORE_LAW_FILE"
    exit 1
fi

echo "✓ Manifest integrity validated"

# Set environment
export VEC3_ROOT="$VEC3_ROOT"
export PHENO_PERSONA="${PHENO_PERSONA:-default}"
export RUNTIME_LOG_LEVEL="${RUNTIME_LOG_LEVEL:-info}"

echo "✓ Environment configured"
echo "  VEC3_ROOT: $VEC3_ROOT"
echo "  PHENO_PERSONA: $PHENO_PERSONA"
echo "  LOG_LEVEL: $RUNTIME_LOG_LEVEL"

# Update system state
cat > "$VEC3_ROOT/var/state/system.json" << EOF
{
  "system_state": "starting",
  "active_persona": "$PHENO_PERSONA",
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pico_phase": "acquire"
}
EOF

# Log startup
STARTUP_LOG="$VEC3_ROOT/var/logs/startup.log"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] System starting with persona: $PHENO_PERSONA" >> "$STARTUP_LOG"

# Check for Imprint.ID integration
if pgrep -f "imprint" > /dev/null 2>&1; then
    echo "✓ Imprint.ID detected (running)"
else
    echo "⚠ Imprint.ID not detected - limited functionality available"
fi

# Start PHENO runner in background
echo ""
echo "Starting PHENO runner..."
"$VEC3_ROOT/lib/runners/run.rb" serve &
RUNNER_PID=$!

# Update state to running
cat > "$VEC3_ROOT/var/state/system.json" << EOF
{
  "system_state": "running",
  "active_persona": "$PHENO_PERSONA",
  "runner_pid": $RUNNER_PID,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pico_phase": "ready"
}
EOF

echo "✓ PHENO runner started (PID: $RUNNER_PID)"

# Log successful startup
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] System started successfully (PID: $RUNNER_PID)" >> "$STARTUP_LOG"

# Wait for termination signal
echo ""
echo "▛▞ PHENO vec3 System Running ▞▞"
echo "   Runner PID: $RUNNER_PID"
echo "   Persona: $PHENO_PERSONA"
echo "   Logs: tail -f var/logs/startup.log"
echo ""
echo "   Press Ctrl+C to stop"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Shutting down PHENO system..."

    # Update state
    cat > "$VEC3_ROOT/var/state/system.json" << EOF
    {
      "system_state": "stopping",
      "active_persona": "$PHENO_PERSONA",
      "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "pico_phase": "complete"
    }
    EOF

    # Stop runner
    if kill -0 $RUNNER_PID 2>/dev/null; then
        kill $RUNNER_PID
        wait $RUNNER_PID 2>/dev/null
        echo "✓ Runner stopped"
    fi

    # Final state
    cat > "$VEC3_ROOT/var/state/system.json" << EOF
    {
      "system_state": "stopped",
      "active_persona": "$PHENO_PERSONA",
      "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "pico_phase": "idle"
    }
    EOF

    # Log shutdown
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] System shutdown complete" >> "$STARTUP_LOG"

    echo "✓ System shutdown complete"
    echo ":: ∎"
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM

# Wait for runner to finish
wait $RUNNER_PID