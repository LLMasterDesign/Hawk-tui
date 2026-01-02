#!/usr/bin/env ruby
#
# RUN.RB :: CMD.BRIDGE Dispatcher and Tool Runner
# Enhanced dispatcher with tool discovery, command parsing, and execution
#

require 'fileutils'
require 'json'
require 'time'

# Add vec3 to path for requires
VEC3_ROOT = File.expand_path('vec3', File.dirname(__FILE__))
$LOAD_PATH.unshift(VEC3_ROOT)

require './vec3/dev/ops/lib/helpers.rb'
require './vec3/dev/ops/cache/redis.rb'

class CMDDispatcher
  include Helpers

  def initialize
    @vec3_root = VEC3_ROOT

    # Check activation key first
    check_activation

    @commands = {
      'serve' => method(:cmd_serve),
      'shell' => method(:cmd_shell),
      'ask' => method(:cmd_ask),
      'clock' => method(:cmd_clock),
      'heartbeat' => method(:cmd_heartbeat),
      'telegram' => method(:cmd_telegram),
      'rest' => method(:cmd_rest),
      'install' => method(:cmd_install),
      'validate' => method(:cmd_validate),
      'test' => method(:cmd_test),
      'status' => method(:cmd_status),
      'help' => method(:cmd_help)
    }
  end

  def check_activation
    # .3ox directory is one level up from vec3
    dot3ox_dir = File.dirname(@vec3_root)
    key_file = File.join(dot3ox_dir, '3ox.key')
    unless File.exist?(key_file) && !File.read(key_file).strip.empty?
      puts "▛▞// ERROR: 3ox.key not found or empty. Please create activation key."
      puts "▛▞// Create: echo 'your_activation_key_here' > .3ox/3ox.key"
      exit 1
    end
  end

  def find_tool(name)
    # Search order: rc/run/, dev/ops/, dev/tools/, dev/providers/, dev/io/, bin/
    search_paths = [
      File.join(@vec3_root, 'rc', 'run'),
      File.join(@vec3_root, 'dev', 'ops'),
      File.join(@vec3_root, 'dev', 'tools'),
      File.join(@vec3_root, 'dev', 'providers'),
      File.join(@vec3_root, 'dev', 'io'),
      File.join(@vec3_root, 'bin')
    ]

    search_paths.each do |path|
      next unless File.directory?(path)

      # Look for exact match first
      tool_path = File.join(path, name)
      return tool_path if File.exist?(tool_path) && File.executable?(tool_path)

      # Look for .rb extension
      tool_rb = "#{tool_path}.rb"
      return tool_rb if File.exist?(tool_rb)

      # Look for .sh extension
      tool_sh = "#{tool_path}.sh"
      return tool_sh if File.exist?(tool_sh)
    end

    nil
  end

  def dispatch_tool(name, *args)
    tool_path = find_tool(name)

    unless tool_path
      puts "▛▞// ERROR: Tool '#{name}' not found"
      log_operation('tool_dispatch', 'ERROR', "Tool not found: #{name}")
      return false
    end

    log_operation('tool_dispatch', 'START', "Tool: #{name}, Args: #{args.join(' ')}")

    begin
      # Execute the tool
      if tool_path.end_with?('.rb')
        system('ruby', tool_path, *args)
      elsif tool_path.end_with?('.sh')
        system('bash', tool_path, *args)
      else
        system(tool_path, *args)
      end

      success = $?.success?
      log_operation('tool_dispatch', success ? 'COMPLETE' : 'ERROR', "Tool: #{name}, Exit: #{$?.exitstatus}")
      success

    rescue => e
      log_operation('tool_dispatch', 'ERROR', "Tool: #{name}, Exception: #{e.message}")
      puts "▛▞// ERROR: Tool execution failed: #{e.message}"
      false
    end
  end

  # ============================================================================
  # COMMAND IMPLEMENTATIONS
  # ============================================================================

  def cmd_serve(args)
    puts "▛▞// Starting Station file watcher..."
    dispatch_tool('station.serve')
  end

  def cmd_shell(args)
    puts "▛▞// Starting interactive shell..."
    dispatch_tool('shell.interactive')
  end

  def cmd_ask(args)
    prompt = args.join(' ')
    if prompt.empty?
      puts "▛▞// Usage: run.rb ask <prompt>"
      return
    end

    puts "▛▞// Asking AI provider..."
    dispatch_tool('ask', prompt)
  end

  def cmd_clock(args)
    sirius = sirius_time()
    local_time = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
    puts "▛▞// Local time: #{local_time}"
    puts "▛▞// Sirius time: #{sirius}"
  end

  def cmd_heartbeat(args)
    status = args[0] || 'active'
    puts "▛▞// Sending heartbeat (#{status})..."
    dispatch_tool('heartbeat', 'CMD.BRIDGE', status)
  end

  def cmd_telegram(args)
    puts "▛▞// Starting Telegram bot..."
    dispatch_tool('bot')
  end

  def cmd_rest(args)
    puts "▛▞// Starting REST API server..."
    dispatch_tool('rest.api')
  end

  def cmd_install(args)
    puts "▛▞// Running installation..."
    install_script = File.join(@vec3_root, 'boot', 'install.sh')
    if File.exist?(install_script)
      system('bash', install_script)
    else
      puts "▛▞// Install script not found"
    end
  end

  def cmd_validate(args)
    config_path = args[0] || File.join(@vec3_root, 'rc', 'personas', 'default.cfg')

    if File.exist?(config_path)
      puts "▛▞// ✓ Valid: #{config_path}"
      puts "▛▞// Size: #{File.size(config_path)} bytes"
      puts "▛▞// Modified: #{File.mtime(config_path)}"
    else
      puts "▛▞// ✗ Missing: #{config_path}"
      exit 1
    end

    # Additional validations
    validate_system_components
  end

  def validate_system_components
    components = [
      ['vec3/dev/ops/lib/helpers.rb', 'Helpers module'],
      ['vec3/dev/ops/cache/redis.rb', 'Redis cache module'],
      ['vec3/dev/ops/station.serve.rb', 'Station watcher'],
      ['vec3/dev/providers/ask.sh', 'AI provider bridge'],
      ['vec3/dev/ops/shell.interactive.rb', 'Interactive shell'],
      ['vec3/bin/rest.api.rb', 'REST API server'],
      ['vec3/dev/io/tg/bot.rb', 'Telegram bot'],
      ['vec3/bin/sirius.clock.rb', 'Sirius clock'],
      ['3ox.key', 'Activation key'],
      ['3ox.log', 'Operation log']
    ]

    puts "▛▞// System Components:"
    all_valid = true

    components.each do |path, description|
      full_path = File.exist?(path) ? path : File.join(@vec3_root, path)
      if File.exist?(full_path)
        puts "▛▞// ✓ #{description}: #{File.basename(path)}"
      else
        puts "▛▞// ✗ #{description}: #{File.basename(path)} (MISSING)"
        all_valid = false
      end
    end

    puts "▛▞// Overall: #{all_valid ? 'VALID' : 'INVALID'}"
    exit 1 unless all_valid
  end

  def cmd_test(args)
    puts "▛▞// Running CMD.BRIDGE tests..."

    # Basic connectivity tests
    tests = [
      ['Redis connection', -> { RedisCache.redis_available? && RedisCache.get_redis_connection ? true : false }],
      ['File system access', -> { File.writable?(File.join(@vec3_root, 'var')) }],
      ['Log writing', -> {
        begin
          log_operation('test', 'INFO', 'Test log entry')
          true
        rescue
          false
        end
      }],
      ['Receipt storage', -> {
        test_receipt = { 'test' => true, 'timestamp' => Time.now.utc.iso8601 }
        RedisCache.redis_available? ? RedisCache.store_receipt('test_123', test_receipt) : true
      }]
    ]

    passed = 0
    total = tests.length

    tests.each do |name, test_proc|
      begin
        result = test_proc.call
        if result
          puts "▛▞// ✓ #{name}"
          passed += 1
        else
          puts "▛▞// ✗ #{name}"
        end
      rescue => e
        puts "▛▞// ✗ #{name} (ERROR: #{e.message})"
      end
    end

    puts "▛▞// Tests: #{passed}/#{total} passed"

    if passed == total
      puts "▛▞// ✓ CMD.BRIDGE is operational!"
      exit 0
    else
      puts "▛▞// ✗ Some tests failed"
      exit 1
    end
  end

  def cmd_status(args)
    puts "▛▞// CMD.BRIDGE Status Report"
    puts "▛▞// Sirius time: #{sirius_time()}"
    puts "▛▞// Version: 3.0.0"

    # Redis status
    if RedisCache.redis_available?
      health = RedisCache.redis_health_check
      puts "▛▞// Redis: #{health[:status]}"
      if health[:status] == 'healthy'
        puts "▛▞//   DB Size: #{health[:db_size]} keys"
        puts "▛▞//   Response: #{health[:response_time_ms]}ms"
      end
    else
      puts "▛▞// Redis: unavailable"
    end

    # Queue status
    if RedisCache.redis_available?
      queue_depth = RedisCache.queue_length('jobs')
      puts "▛▞// Job Queue: #{queue_depth} items"
    end

    # Running processes
    running_processes = check_running_processes
    puts "▛▞// Running Services: #{running_processes.join(', ')}"

    # File system status
    var_dir = File.join(@vec3_root, 'var')
    if File.directory?(var_dir)
      receipts_count = Dir.glob(File.join(var_dir, 'receipts', '**', '*.json')).length
      puts "▛▞// Stored Receipts: #{receipts_count}"
    end
  end

  def check_running_processes
    processes = []

    # Check for station watcher
    if `pgrep -f "station.serve.rb" 2>/dev/null`.strip != ''
      processes << 'station'
    end

    # Check for REST API
    if `pgrep -f "rest.api.rb" 2>/dev/null`.strip != ''
      processes << 'rest-api'
    end

    # Check for Telegram bot
    if `pgrep -f "bot.rb" 2>/dev/null`.strip != ''
      processes << 'telegram'
    end

    processes.empty? ? ['none'] : processes
  end

  def cmd_help(args)
    puts "▛▞// CMD.BRIDGE Dispatcher Commands:"
    puts "▛▞//"
    puts "▛▞// Core Services:"
    puts "▛▞//   serve       - Start file watcher (station)"
    puts "▛▞//   shell       - Start interactive shell"
    puts "▛▞//   rest        - Start REST API server"
    puts "▛▞//   telegram    - Start Telegram bot"
    puts "▛▞//"
    puts "▛▞// Utilities:"
    puts "▛▞//   ask <text>  - Ask AI assistant"
    puts "▛▞//   clock       - Show current Sirius time"
    puts "▛▞//   heartbeat   - Send system heartbeat"
    puts "▛▞//   status      - Show system status"
    puts "▛▞//"
    puts "▛▞// Management:"
    puts "▛▞//   install     - Run installation"
    puts "▛▞//   validate    - Validate configuration"
    puts "▛▞//   test        - Run system tests"
    puts "▛▞//   help        - Show this help"
    puts "▛▞//"
    puts "▛▞// Usage: run.rb <command> [args...]"
  end

  # ============================================================================
  # MAIN EXECUTION
  # ============================================================================

  def run(args)
    command = args.shift || 'help'

    if @commands.key?(command)
      log_operation('dispatcher', 'START', "Command: #{command}, Args: #{args.join(' ')}")
      @commands[command].call(args)
      log_operation('dispatcher', 'COMPLETE', "Command: #{command}")
    else
      # Try to dispatch as a tool
      if dispatch_tool(command, *args)
        # Tool executed successfully
      else
        puts "▛▞// ERROR: Unknown command '#{command}'"
        cmd_help([])
        exit 1
      end
    end
  end
end

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

if __FILE__ == $0
  begin
    dispatcher = CMDDispatcher.new
    dispatcher.run(ARGV)
  rescue => e
    puts "▛▞// FATAL ERROR: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end