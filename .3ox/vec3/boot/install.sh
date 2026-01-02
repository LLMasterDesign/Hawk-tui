#!/bin/bash
# install.sh :: PHENO vec3 Framework Installation Script

set -e

VEC3_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_NAME="PHENO vec3 Installer"

echo "▛//▞▞ ⟦⎊⟧ :: ⧗-25.125 // $SCRIPT_NAME ▞▞"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check Ruby
if ! command -v ruby &> /dev/null; then
    echo "✗ Ruby is required but not installed"
    echo "  Install Ruby 2.7+ and try again"
    exit 1
fi

RUBY_VERSION=$(ruby -v | grep -oP '\d+\.\d+\.\d+')
echo "✓ Ruby detected: $RUBY_VERSION"

# Check if we're in the right directory
if [ ! -d "$VEC3_ROOT/rc/core" ]; then
    echo "✗ Not in vec3 directory structure"
    echo "  Run from: .3ox/vec3/boot/"
    exit 1
fi

echo "✓ vec3 directory structure verified"

# Create required directories
echo ""
echo "Creating runtime directories..."
mkdir -p "$VEC3_ROOT/var/"{logs,receipts,queue,cache,state,locks,health,wrkdsk}
mkdir -p "$VEC3_ROOT/dev/"{tests,fixtures}
mkdir -p "$VEC3_ROOT/tmp"

echo "✓ Runtime directories created"

# Set permissions
echo ""
echo "Setting permissions..."
chmod +x "$VEC3_ROOT/lib/runners/run.rb"
chmod +x "$VEC3_ROOT/boot/start.sh"

if [ -f "$VEC3_ROOT/bin/brains" ]; then
    chmod +x "$VEC3_ROOT/bin/brains"
fi

echo "✓ Permissions set"

# Validate configuration
echo ""
echo "Validating configuration..."

# Check core files
CORE_FILES=(
    "rc/core/core.law.sxsl"
    "rc/core/channels.sxsl"
    "rc/core/order.sxsl"
    "rc/core/responder.authority.sxsl"
    "rc/core/receipt.schema.json"
)

for file in "${CORE_FILES[@]}"; do
    if [ -f "$VEC3_ROOT/$file" ]; then
        echo "✓ $file"
    else
        echo "✗ Missing: $file"
        exit 1
    fi
done

# Check persona files
PERSONA_FILES=(
    "rc/personas/default.cfg"
    "rc/personas/raven.cfg"
    "rc/personas/noctua.cfg"
)

for file in "${PERSONA_FILES[@]}"; do
    if [ -f "$VEC3_ROOT/$file" ]; then
        echo "✓ $file"
    else
        echo "✗ Missing: $file"
        exit 1
    fi
done

echo ""
echo "✓ Configuration validation complete"

# Create initial state files
echo ""
echo "Initializing state files..."

# Create initial health status
cat > "$VEC3_ROOT/var/health/status.json" << 'EOF'
{
  "status": "healthy",
  "version": "1.0.0",
  "installed_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "components": {
    "core": "loaded",
    "channels": "ready",
    "personas": "configured",
    "runners": "available"
  }
}
EOF

# Create initial state
cat > "$VEC3_ROOT/var/state/system.json" << 'EOF'
{
  "system_state": "initialized",
  "active_persona": "default",
  "last_updated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "pico_phase": "ready"
}
EOF

echo "✓ State files initialized"

# Test basic functionality
echo ""
echo "Testing basic functionality..."

if "$VEC3_ROOT/lib/runners/run.rb" validate > /dev/null 2>&1; then
    echo "✓ PHENO runner functional"
else
    echo "✗ PHENO runner test failed"
    exit 1
fi

echo ""
echo "▛▞ $SCRIPT_NAME Complete ▞▞"
echo ""
echo "PHENO vec3 framework is ready!"
echo ""
echo "Next steps:"
echo "  1. Start the system: ./boot/start.sh"
echo "  2. Test with: ruby lib/runners/run.rb test"
echo "  3. Check logs: tail -f var/logs/startup.log"
echo ""
echo ":: ∎"