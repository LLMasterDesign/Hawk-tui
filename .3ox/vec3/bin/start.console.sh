#!/bin/bash
###▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂###
# ▛//▞▞ ⟦⎊⟧ :: ⧗-25.145 // START.CONSOLE :: Quick Launcher ▞▞

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "▛▞ Starting 3OX Console Server..."
echo ""

cd "$SCRIPT_DIR"
ruby serve.console.rb
