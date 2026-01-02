#!/usr/bin/env ruby
#
# SHELL.INTERACTIVE.RB :: Interactive Shell for CMD.BRIDGE
# Minimal implementation with session management and Redis-backed memory
#

require 'readline'
require 'securerandom'
require_relative 'lib/helpers.rb'
require_relative 'cache/redis.rb'

class CMDShell
  include Helpers

  def initialize
    @session_id = generate_session_id
    @running = true
    @history = []
    @commands = {
      'help' => method(:cmd_help),
      'exit' => method(:cmd_exit),
      'quit' => method(:cmd_exit),
      'clock' => method(:cmd_clock),
      'sirius' => method(:cmd_clock),
      'session' => method(:cmd_session),
      'status' => method(:cmd_status),
      'ask' => method(:cmd_ask),
      'history' => method(:cmd_history),
      'clear' => method(:cmd_clear),
      'heartbeat' => method(:cmd_heartbeat)
    }

    # Set session environment
    ENV['CMD_SESSION_ID'] = @session_id

    # Initialize session in Redis if available
    init_session

    log_operation('shell_start', 'COMPLETE', "Session: #{@session_id}")
  end

  def generate_session_id
    "shell-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
  end

  def init_session
    session_data = {
      session_id: @session_id,
      started_at: Time.now.utc.iso8601,
      sirius_start: sirius_time(),
      type: 'interactive_shell',
      commands_executed: 0,
      last_activity: Time.now.utc.iso8601
    }

    if RedisCache.redis_available?
      RedisCache.store_session(@session_id, session_data, 86400) # 24 hours
    end
  end

  def update_session_activity
    if RedisCache.redis_available?
      session_data = RedisCache.get_session(@session_id) || {}
      session_data['last_activity'] = Time.now.utc.iso8601
      session_data['commands_executed'] = (session_data['commands_executed'] || 0) + 1
      RedisCache.store_session(@session_id, session_data, 86400)
    end
  end

  def prompt
    sirius = sirius_time()
    "▛▞// CMD.BRIDGE [#{sirius}] > "
  end

  def print_banner
    sirius = sirius_time()
    puts "▛//▞▞ ⟦⎊⟧ :: #{sirius} // CMD.BRIDGE INTERACTIVE SHELL ▞▞"
    puts "▛▞// Session: #{@session_id}"
    puts "▛▞// Type 'help' for commands, 'exit' to quit"
    puts "▛▞// Sirius time: #{sirius}"
    puts
  end

  def run
    print_banner

    while @running
      begin
        input = Readline.readline(prompt, true)
        break unless input

        input = input.strip
        next if input.empty?

        @history << input
        process_command(input)

      rescue Interrupt
        puts "\n▛▞// Use 'exit' to quit"
      rescue => e
        puts "▛▞// Error: #{e.message}"
        log_operation('shell_error', 'ERROR', "Command failed: #{e.message}")
      end
    end

    cleanup
  end

  def process_command(input)
    parts = input.split(/\s+/, 2)
    command = parts[0].downcase
    args = parts[1] || ''

    if @commands.key?(command)
      update_session_activity
      @commands[command].call(args)
    else
      # Default to ask command
      cmd_ask(input)
    end
  end

  # ============================================================================
  # COMMAND IMPLEMENTATIONS
  # ============================================================================

  def cmd_help(args)
    puts "▛▞// CMD.BRIDGE Interactive Shell Commands:"
    puts "▛▞//"
    puts "▛▞// help          - Show this help"
    puts "▛▞// clock         - Show current Sirius time"
    puts "▛▞// session       - Show session information"
    puts "▛▞// status        - Show system status"
    puts "▛▞// ask <prompt>  - Ask the AI assistant"
    puts "▛▞// history       - Show command history"
    puts "▛▞// heartbeat     - Send heartbeat"
    puts "▛▞// clear         - Clear screen"
    puts "▛▞// exit          - Exit shell"
    puts "▛▞//"
    puts "▛▞// Any other input is sent to the AI assistant"
  end

  def cmd_exit(args)
    @running = false
    puts "▛▞// Goodbye!"
  end

  def cmd_clock(args)
    sirius = sirius_time()
    local_time = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
    puts "▛▞// Local time: #{local_time}"
    puts "▛▞// Sirius time: #{sirius}"
  end

  def cmd_session(args)
    session_data = RedisCache.redis_available? ? RedisCache.get_session(@session_id) : nil

    puts "▛▞// Session Information:"
    puts "▛▞// ID: #{@session_id}"
    puts "▛▞// Started: #{session_data ? session_data['started_at'] : 'N/A'}"
    puts "▛▞// Sirius start: #{session_data ? session_data['sirius_start'] : 'N/A'}"
    puts "▛▞// Commands: #{session_data ? session_data['commands_executed'] : 0}"
    puts "▛▞// Last activity: #{session_data ? session_data['last_activity'] : 'N/A'}"
    puts "▛▞// Redis: #{RedisCache.redis_available? ? 'available' : 'unavailable'}"
  end

  def cmd_status(args)
    puts "▛▞// System Status:"

    # Redis status
    redis_health = RedisCache.redis_available? ? RedisCache.redis_health_check : { status: 'unavailable' }
    puts "▛▞// Redis: #{redis_health[:status]}"

    # Queue status
    if RedisCache.redis_available?
      queue_depth = RedisCache.queue_length('jobs')
      puts "▛▞// Job queue: #{queue_depth} items"
    end

    # File watcher status (simplified check)
    station_pid = find_station_pid
    puts "▛▞// Station watcher: #{station_pid ? 'running (PID: ' + station_pid.to_s + ')' : 'not running'}"

    # Memory usage (simplified)
    puts "▛▞// Memory: #{get_memory_usage_mb} MB"
  end

  def cmd_ask(args)
    return if args.strip.empty?

    puts "▛▞// Thinking..."

    # Call ask.sh script
    ask_script = File.join(File.dirname(__FILE__), '..', 'providers', 'ask.sh')

    if File.exist?(ask_script)
      begin
        # Execute ask.sh and capture output
        response = `#{ask_script} "#{args}" 2>/dev/null`

        if $?.success? && !response.empty?
          puts "▛▞// Response:"
          puts response
        else
          puts "▛▞// Failed to get response from AI provider"
          log_operation('shell_ask', 'ERROR', "Failed: #{args[0..50]}...")
        end
      rescue => e
        puts "▛▞// Error calling AI provider: #{e.message}"
      end
    else
      puts "▛▞// AI provider not available (ask.sh not found)"
    end
  end

  def cmd_history(args)
    puts "▛▞// Command History:"
    @history.each_with_index do |cmd, idx|
      puts "▛▞// #{idx + 1}: #{cmd}"
    end
  end

  def cmd_clear(args)
    system('clear') || system('cls') || puts("\n" * 50)
  end

  def cmd_heartbeat(args)
    heartbeat_script = File.join(File.dirname(__FILE__), 'lib', 'heartbeat.rb')

    if File.exist?(heartbeat_script)
      system('ruby', heartbeat_script, 'CMD.BRIDGE', 'active')
      puts "▛▞// Heartbeat sent"
    else
      puts "▛▞// Heartbeat script not found"
    end
  end

  # ============================================================================
  # UTILITY METHODS
  # ============================================================================

  def find_station_pid
    # Look for station.serve.rb processes
    begin
      ps_output = `ps aux | grep "station.serve.rb" | grep -v grep`
      if ps_output =~ /^\w+\s+(\d+)/
        return $1.to_i
      end
    rescue
      # Ignore errors
    end
    nil
  end

  def get_memory_usage_mb
    begin
      # Try to get RSS from /proc/self/status (Linux)
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if status =~ /VmRSS:\s+(\d+)\s+kB/
          return ($1.to_i / 1024.0).round(1)
        end
      end
    rescue
      # Ignore errors
    end
    0.0
  end

  def cleanup
    log_operation('shell_end', 'COMPLETE', "Session: #{@session_id}, Commands: #{@history.length}")

    # Update final session data
    if RedisCache.redis_available?
      session_data = RedisCache.get_session(@session_id) || {}
      session_data['ended_at'] = Time.now.utc.iso8601
      session_data['duration_seconds'] = (Time.parse(session_data['ended_at']) - Time.parse(session_data['started_at'])).to_i
      RedisCache.store_session(@session_id, session_data, 86400 * 7) # Keep for a week
    end

    RedisCache.disconnect if RedisCache.redis_available?
  end
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __FILE__ == $0
  begin
    shell = CMDShell.new
    shell.run
  rescue => e
    puts "▛▞// Fatal error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end