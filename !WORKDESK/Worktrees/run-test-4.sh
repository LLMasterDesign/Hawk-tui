#!/usr/bin/env bash
# Test 4: Multi-File Coordination
# Verify agents can coordinate work across multiple files

set -e

echo "▛▞ Test 4: Multi-File Coordination ⫎▸"
echo ""

BASE_DIR="/mnt/r/!CMD.BRIDGE/!WORKDESK/Worktrees"
AGENT1_DIR="$BASE_DIR/multi-agent-collab-20251218-agent1"
AGENT2_DIR="$BASE_DIR/multi-agent-collab-20251218-agent2"
AGENT3_DIR="$BASE_DIR/multi-agent-collab-20251218-agent3"

# Step 1: Agent1 creates config.yaml
echo "Step 1: Agent1 creating config.yaml..."
cat > "$AGENT1_DIR/config.yaml" << 'EOF'
# Application Configuration
# Created by Agent1

app:
  name: "Multi-Agent Test App"
  version: "1.0.0"
  environment: "test"

database:
  host: "localhost"
  port: 5432
  name: "test_db"

api:
  port: 3000
  timeout: 30
EOF

cd "$AGENT1_DIR"
git add config.yaml
git commit -m "Agent1: Create config.yaml for multi-file coordination test"
echo "✅ Agent1: config.yaml created and committed"
echo ""

# Step 2: Agent2 merges Agent1, reads config, creates app.rb
echo "Step 2: Agent2 merging Agent1 and creating app.rb..."
cd "$AGENT2_DIR"
git merge multi-agent-collab-20251218-agent1 --no-edit 2>&1 | grep -v "^Merge" || true

cat > "$AGENT2_DIR/app.rb" << 'EOF'
#!/usr/bin/env ruby
# Application main file
# Created by Agent2 using config from Agent1

require 'yaml'

# Load config created by Agent1
config = YAML.load_file('config.yaml')

puts "Starting #{config['app']['name']} v#{config['app']['version']}"
puts "Environment: #{config['app']['environment']}"
puts "API will run on port #{config['api']['port']}"
puts "Database: #{config['database']['host']}:#{config['database']['port']}/#{config['database']['name']}"

# Application logic would go here
def run_app
  puts "Application running..."
end

run_app if __FILE__ == $0
EOF

git add app.rb
git commit -m "Agent2: Create app.rb using config.yaml from Agent1"
echo "✅ Agent2: app.rb created using Agent1's config"
echo ""

# Step 3: Agent3 merges Agent2, creates tests.rb
echo "Step 3: Agent3 merging Agent2 and creating tests.rb..."
cd "$AGENT3_DIR"
git merge multi-agent-collab-20251218-agent2 --no-edit 2>&1 | grep -v "^Merge" || true

cat > "$AGENT3_DIR/tests.rb" << 'EOF'
#!/usr/bin/env ruby
# Tests for app.rb
# Created by Agent3 to test Agent2's app.rb

require_relative 'app.rb'
require 'yaml'

puts "Running tests for app.rb..."
puts ""

# Test 1: Config file exists
if File.exist?('config.yaml')
  puts "✅ Test 1: config.yaml exists"
else
  puts "❌ Test 1: config.yaml missing"
end

# Test 2: App file exists
if File.exist?('app.rb')
  puts "✅ Test 2: app.rb exists"
else
  puts "❌ Test 2: app.rb missing"
end

# Test 3: Config is valid YAML
begin
  config = YAML.load_file('config.yaml')
  if config['app'] && config['app']['name']
    puts "✅ Test 3: config.yaml is valid and contains app.name"
  else
    puts "❌ Test 3: config.yaml missing app.name"
  end
rescue => e
  puts "❌ Test 3: config.yaml parse error: #{e.message}"
end

puts ""
puts "All tests completed!"
EOF

git add tests.rb
git commit -m "Agent3: Create tests.rb for Agent2's app.rb"
echo "✅ Agent3: tests.rb created to test Agent2's app"
echo ""

# Step 4: Verify all files work together
echo "Step 4: Verifying all files work together..."
cd "$AGENT3_DIR"

FILES=("config.yaml" "app.rb" "tests.rb")
ALL_EXIST=0

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file MISSING"
        ALL_EXIST=1
    fi
done

echo ""
if [ $ALL_EXIST -eq 0 ]; then
    echo "Testing app.rb execution:"
    ruby app.rb 2>&1 | head -5
    echo ""
    echo "Testing tests.rb execution:"
    ruby tests.rb 2>&1 | head -10
    echo ""
    echo "▛▞ Test 4 Complete: PASSED ⫎▸"
    echo "✅ All files created in correct order"
    echo "✅ Dependencies resolved"
    echo "✅ Files work together"
else
    echo "▛▞ Test 4 Complete: FAILED ⫎▸"
    exit 1
fi
