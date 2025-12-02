#!/bin/bash
# Holodeck Verification Script
# Tests system health and updates tasker.cfg with results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_FILE="$SCRIPT_DIR/lib/Notes/tasker.cfg"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "▞ Holodeck Verification ▞"
echo "=========================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
SERVER_HEALTH="ok"
API_ENDPOINTS="all_passing"
UI_RENDERING="ok"

# Check if server is running
echo -n "Checking server status... "
if curl -s http://localhost:8080/api/data > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server running${NC}"
    SERVER_HEALTH="ok"
else
    echo -e "${RED}✗ Server not responding${NC}"
    SERVER_HEALTH="failed"
    API_ENDPOINTS="failed"
fi

# Test API endpoints if server is up
if [ "$SERVER_HEALTH" = "ok" ]; then
    echo -n "Testing /api/data... "
    if curl -s http://localhost:8080/api/data | grep -q "\[\|{"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        API_ENDPOINTS="partial"
    fi
    
    echo -n "Testing /api/unmapped... "
    if curl -s http://localhost:8080/api/unmapped | grep -q "\[\|{"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        API_ENDPOINTS="partial"
    fi
    
    echo -n "Testing dashboard.html... "
    if curl -s http://localhost:8080/dashboard.html | grep -q "HOLODECK\|Holodeck"; then
        echo -e "${GREEN}✓${NC}"
        UI_RENDERING="ok"
    else
        echo -e "${RED}✗${NC}"
        UI_RENDERING="failed"
    fi
fi

# Update tasker.cfg (requires python3 with tomli or manual sed)
echo ""
echo "Updating tasker.cfg..."

# Use Python to update TOML file properly
python3 << EOF
import re
from datetime import datetime

cfg_file = "$CFG_FILE"
timestamp = "$TIMESTAMP"

try:
    with open(cfg_file, 'r') as f:
        content = f.read()
    
    # Update testing section
    content = re.sub(r'last_run = ".*"', f'last_run = "{timestamp}"', content)
    content = re.sub(r'server_health = ".*"', f'server_health = "$SERVER_HEALTH"', content)
    content = re.sub(r'api_endpoints = ".*"', f'api_endpoints = "$API_ENDPOINTS"', content)
    content = re.sub(r'ui_rendering = ".*"', f'ui_rendering = "$UI_RENDERING"', content)
    
    with open(cfg_file, 'w') as f:
        f.write(content)
    
    print("✓ tasker.cfg updated")
except Exception as e:
    print(f"✗ Failed to update tasker.cfg: {e}")
EOF

echo ""
echo "=========================="
echo "Verification complete!"
echo "Results saved to tasker.cfg"

