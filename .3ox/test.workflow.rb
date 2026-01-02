#!/usr/bin/env ruby
#
# TEST.WORKFLOW.RB :: End-to-End Workflow Test for CMD.BRIDGE
# Tests file drop, analysis, conversation context, and Redis integration
#

require 'fileutils'
require 'json'

# Test configuration
TEST_DROP_DIR = ENV['TEST_DROP_DIR'] || '/root/!CMD.BRIDGE/!1N.3OX'
VEC3_ROOT = '/root/!CMD.BRIDGE/.3ox/vec3'
TEST_SESSION = 'test_session_' + Time.now.to_i.to_s

puts "///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ::[0xA4]::"
puts "▛//▞▞ WORKFLOW TEST :: CMD.BRIDGE ▞▞"
puts

# ============================================================================
# TEST 1: Redis Connectivity
# ============================================================================

puts "▛▞// TEST 1: Redis Connectivity"

redis_test = `cd #{VEC3_ROOT} && ruby -r./dev/ops/cache/redis.rb -e "puts RedisCache.redis_available? ? 'PASS' : 'FAIL'" 2>&1`.strip

if redis_test.include?('PASS')
  puts "▛▞//   ✓ Redis available"
else
  puts "▛▞//   ✗ Redis not available - some features will not work"
  puts "▛▞//   Start Redis: redis-server"
end

puts

# ============================================================================
# TEST 2: Conversation Context (Memory Test)
# ============================================================================

puts "▛▞// TEST 2: Conversation Context (Redis Memory)"

# Add test messages
puts "▛▞//   Adding test messages..."
system("cd #{VEC3_ROOT} && ruby dev/ops/conversation.context.rb add --session #{TEST_SESSION} --role user --message 'We are testing the file analysis workflow'")
system("cd #{VEC3_ROOT} && ruby dev/ops/conversation.context.rb add --session #{TEST_SESSION} --role assistant --message 'I will help analyze files dropped into the watch folder'")
system("cd #{VEC3_ROOT} && ruby dev/ops/conversation.context.rb add --session #{TEST_SESSION} --role user --message 'What were we talking about?'")

# Query context
puts "▛▞//   Querying context..."
system("cd #{VEC3_ROOT} && ruby dev/ops/conversation.context.rb context --session #{TEST_SESSION}")

puts

# ============================================================================
# TEST 3: File Analysis
# ============================================================================

puts "▛▞// TEST 3: File Analysis"

# Create test file
test_file = File.join('/tmp', 'test_document.md')
File.write(test_file, <<~CONTENT)
  # Test Document
  
  This is a test document for the file analysis workflow.
  It contains some sample content that should be analyzed.
  
  ## Topics
  - File processing
  - Workflow automation
  - Redis integration
CONTENT

puts "▛▞//   Created test file: #{test_file}"

# Analyze without execution
puts "▛▞//   Running analysis..."
system("cd #{VEC3_ROOT} && ruby dev/ops/file.analyzer.rb #{test_file}")

puts

# ============================================================================
# TEST 4: File Drop Simulation
# ============================================================================

puts "▛▞// TEST 4: File Drop Workflow"

unless File.directory?(TEST_DROP_DIR)
  puts "▛▞//   Creating drop directory: #{TEST_DROP_DIR}"
  FileUtils.mkdir_p(TEST_DROP_DIR)
end

# Copy test file to drop zone
dropped_file = File.join(TEST_DROP_DIR, "dropped_#{Time.now.to_i}.md")
FileUtils.cp(test_file, dropped_file)
puts "▛▞//   Dropped file: #{dropped_file}"

# Optionally create a note file
note_file = dropped_file.sub('.md', '.note.txt')
File.write(note_file, "This file needs to be reviewed and moved to the project folder")
puts "▛▞//   Added note: #{note_file}"

puts "▛▞//   File ready for station watcher to process"
puts "▛▞//   (Station will pick it up automatically if running)"

puts

# ============================================================================
# TEST 5: Job Queue Test
# ============================================================================

puts "▛▞// TEST 5: Job Queue Integration"

# Create a test job
test_job = {
  'job_id' => 'test_' + Time.now.to_i.to_s,
  'job_type' => 'ask',
  'payload' => {
    'prompt' => 'What were we talking about?'
  },
  'session_id' => TEST_SESSION,
  'status' => 'queued',
  'created_at' => Time.now.utc.iso8601
}

test_job_file = '/tmp/test_job.json'
File.write(test_job_file, JSON.pretty_generate(test_job))
puts "▛▞//   Created test job: #{test_job_file}"

# Test job schema validation
validation_result = `cd #{VEC3_ROOT} && ruby -r./lib/job_schema.rb -e "job = JSON.parse(File.read('#{test_job_file}')); puts JobSchema.valid_job?(job) ? 'VALID' : 'INVALID'" 2>&1`.strip
puts "▛▞//   Job validation: #{validation_result}"

puts

# ============================================================================
# TEST 6: Complete Workflow Test
# ============================================================================

puts "▛▞// TEST 6: End-to-End Workflow Status"
puts
puts "▛▞// To test the complete workflow:"
puts "▛▞//"
puts "▛▞// Terminal 1: Start Redis"
puts "▛▞//   $ redis-server"
puts "▛▞//"
puts "▛▞// Terminal 2: Start Station Watcher"
puts "▛▞//   $ cd /root/!CMD.BRIDGE/.3ox"
puts "▛▞//   $ ruby run.rb serve"
puts "▛▞//"
puts "▛▞// Terminal 3: Start Worker"
puts "▛▞//   $ cd /root/!CMD.BRIDGE/.3ox"
puts "▛▞//   $ ruby run.rb worker"
puts "▛▞//"
puts "▛▞// Terminal 4: Test Commands"
puts "▛▞//   $ cd /root/!CMD.BRIDGE/.3ox"
puts "▛▞//   $ ruby run.rb ask \"What were we talking about?\""
puts "▛▞//   $ ruby run.rb status"
puts "▛▞//"
puts "▛▞// File Drop: Copy files to #{TEST_DROP_DIR}"
puts "▛▞//   Station will automatically analyze and process them"
puts

# ============================================================================
# TEST 7: System Status
# ============================================================================

puts "▛▞// TEST 7: System Status"
system("cd /root/!CMD.BRIDGE/.3ox && ruby run.rb status")

puts
puts "▛▞// Test session ID: #{TEST_SESSION}"
puts "▛▞// Test file: #{dropped_file}"
puts "▛▞// Clean up: rm #{test_file} #{test_job_file}"
puts
puts ":: ∎"
