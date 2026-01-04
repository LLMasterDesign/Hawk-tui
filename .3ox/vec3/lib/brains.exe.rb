#!/usr/bin/env ruby
#
# BRAINS.EXE.RB :: Worker Process for CMD.BRIDGE
# Pulls jobs from Redis queue, processes them, and writes results
#

require 'json'
require 'time'
require 'fileutils'
require 'digest'

# Add vec3 to path
VEC3_ROOT = File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH.unshift(VEC3_ROOT) unless $LOAD_PATH.include?(VEC3_ROOT)

require_relative '../dev/ops/lib/helpers.rb'
require_relative '../dev/ops/cache/redis.rb'
require_relative 'job_schema.rb'
require_relative 'imprint.bridge.rb'
require_relative '../dev/ops/conversation.context.rb'
require_relative '../dev/ops/file.analyzer.rb'

class BrainsWorker
  include Helpers

  QUEUE_NAME = 'jobs'
  PROCESSING_QUEUE = 'jobs:processing'
  POLL_INTERVAL = 1  # seconds
  HEARTBEAT_INTERVAL = 30  # seconds
  FILE_SCAN_INTERVAL = 30  # seconds - scan file system
  STATE_UPDATE_INTERVAL = 10  # seconds - update unified state
  HEARTBEAT_TIMEOUT = 90  # seconds - component considered dead

  # Redis keys
  REDIS_STATE_KEY = 'cmd.bridge:unified:state'

  def initialize(worker_id = nil)
    @worker_id = worker_id || generate_worker_id
    @running = false
    @jobs_processed = 0
    @jobs_failed = 0
    @start_time = Time.now
    @last_heartbeat = Time.now
    @last_file_scan = Time.now
    @last_state_update = Time.now
    @file_index = {}

    # Load brain configuration
    @brain_config = load_brain_config
    @provider_cache = {}
    
    # Check Imprint availability
    @imprint_enabled = check_imprint_availability

    # Initialize unified state
    initialize_unified_state

    log_operation('brains_init', 'COMPLETE', "Worker: #{@worker_id}, Imprint: #{@imprint_enabled ? 'enabled' : 'disabled'}")
  end
  
  def check_imprint_availability
    if ImprintBridge.imprint_available?
      log_operation('imprint_check', 'COMPLETE', 'Imprint governance enabled')
      true
    else
      log_operation('imprint_check', 'WARNING', 'Imprint not available, running without governance')
      false
    end
  end

  def generate_worker_id
    hostname = `hostname`.strip rescue 'unknown'
    pid = Process.pid
    "brain_#{hostname}_#{pid}"
  end

  # ============================================================================
  # BRAIN CONFIGURATION
  # ============================================================================

  def load_brain_config
    config_file = File.join(get_vec3_root, 'rc', 'personas', 'default.cfg')
    
    if File.exist?(config_file)
      log_operation('brain_config', 'COMPLETE', "Loaded: #{config_file}")
      # Simple config parser for now
      {
        'name' => 'Default Agent',
        'version' => '1.0.0',
        'providers' => ['openai', 'claude', 'ollama']
      }
    else
      log_operation('brain_config', 'WARNING', 'Using default config')
      {
        'name' => 'Default Agent',
        'version' => '1.0.0',
        'providers' => ['openai']
      }
    end
  end

  # ============================================================================
  # QUEUE OPERATIONS
  # ============================================================================

  def fetch_job
    return nil unless RedisCache.redis_available?

    # Use BRPOPLPUSH for atomic move to processing queue with timeout
    conn = RedisCache.get_redis_connection
    return nil unless conn

    begin
      # RPOPLPUSH atomically moves from queue to processing
      result = conn.rpoplpush("queue:#{QUEUE_NAME}", "queue:#{PROCESSING_QUEUE}")
      
      if result
        job = JSON.parse(result)
        log_operation('job_fetch', 'COMPLETE', "Job: #{job['job_id']}, Type: #{job['job_type']}")
        job
      else
        nil
      end
    rescue => e
      log_operation('job_fetch', 'ERROR', "Error: #{e.message}")
      nil
    end
  end

  def remove_from_processing(job)
    return unless RedisCache.redis_available?

    conn = RedisCache.get_redis_connection
    return unless conn

    begin
      # Remove from processing queue
      job_json = JSON.generate(job)
      conn.lrem("queue:#{PROCESSING_QUEUE}", 1, job_json)
    rescue => e
      log_operation('queue_cleanup', 'ERROR', "Job: #{job['job_id']}, Error: #{e.message}")
    end
  end

  def store_job_result(job)
    return unless RedisCache.redis_available?

    # Store completed job in results with expiry
    result_key = "result:#{job['job_id']}"
    RedisCache.redis_set(result_key, job, 86400 * 7) # 7 days

    # Also update the receipt if one exists
    if job['receipt_id']
      receipt = RedisCache.get_receipt(job['receipt_id'])
      if receipt
        receipt['job_id'] = job['job_id']
        receipt['status'] = job['status']
        receipt['completed_at'] = job['completed_at']
        receipt['result'] = job['result']
        receipt['error'] = job['error']
        RedisCache.store_receipt(job['receipt_id'], receipt)
      end
    end
  end

  # ============================================================================
  # JOB PROCESSING
  # ============================================================================

  def process_job(job)
    unless JobSchema.valid_job?(job)
      log_operation('job_validation', 'ERROR', "Invalid job structure: #{job['job_id']}")
      return
    end

    # Mark as processing
    JobSchema.mark_processing(job, @worker_id)
    log_operation('job_start', 'START', "Job: #{job['job_id']}, Type: #{job['job_type']}")

    # Imprint governance check (if enabled)
    if @imprint_enabled
      validation = ImprintBridge.validate_job(job)
      
      unless validation[:valid]
        log_operation('imprint_validation', 'REFUSE', "Job: #{job['job_id']}, Reason: #{validation[:reason]}")
        
        # Mark as refused
        JobSchema.mark_failed(job, {
          'message' => 'Imprint governance refused execution',
          'reason' => validation[:reason],
          'action' => validation[:action]
        })
        
        store_job_result(job)
        remove_from_processing(job)
        @jobs_failed += 1
        return
      end
      
      log_operation('imprint_validation', 'COMPLETE', "Job: #{job['job_id']}, Tool: #{validation[:tool_id]}")
      job['metadata']['imprint_validated'] = true
      job['metadata']['imprint_tool'] = validation[:tool_id]
    end

    begin
      # Route to appropriate handler
      result = case job['job_type']
      when 'ask'
        handle_ask_job(job)
      when 'ingest.file'
        handle_ingest_job(job)
      when 'telegram'
        handle_telegram_job(job)
      when 'rest.request'
        handle_rest_job(job)
      when 'shell.cmd'
        handle_shell_job(job)
      else
        raise "Unknown job type: #{job['job_type']}"
      end

      # Mark as completed
      receipt_id = generate_receipt_id(job)
      JobSchema.mark_completed(job, result, receipt_id)
      
      # Submit to Imprint if enabled
      if @imprint_enabled && result
        imprint = ImprintBridge.load_active_imprint
        if imprint
          imprint_receipt = ImprintBridge.create_imprint_receipt(job, {
            status: 'completed',
            data: result,
            tools_used: [job['metadata']['imprint_tool']],
            route_id: job['metadata']['route_id']
          }, imprint['imprint_id'])
          
          ImprintBridge.submit_receipt(imprint_receipt)
          log_operation('imprint_receipt', 'COMPLETE', "Receipt: #{receipt_id}")
        end
      end
      
      log_operation('job_complete', 'COMPLETE', "Job: #{job['job_id']}, Receipt: #{receipt_id}")

      @jobs_processed += 1

    rescue => e
      # Mark as failed
      JobSchema.mark_failed(job, {
        'message' => e.message,
        'backtrace' => e.backtrace.first(5)
      })
      log_operation('job_failed', 'ERROR', "Job: #{job['job_id']}, Error: #{e.message}")

      @jobs_failed += 1

      # Requeue if retries remaining
      if job['retry_count'] < job['max_retries']
        requeue_job(job)
      end
    end

    # Store result and cleanup
    store_job_result(job)
    remove_from_processing(job)
  end

  def requeue_job(job)
    return unless RedisCache.redis_available?

    job['status'] = 'queued'
    job['worker_id'] = nil
    
    RedisCache.queue_push(QUEUE_NAME, job)
    log_operation('job_requeue', 'COMPLETE', "Job: #{job['job_id']}, Retry: #{job['retry_count']}")
  end

  def generate_receipt_id(job)
    content = "#{job['job_id']}#{job['created_at']}#{job['job_type']}"
    Digest::SHA256.hexdigest(content)[0..15]
  end

  # ============================================================================
  # JOB HANDLERS
  # ============================================================================

  def handle_ask_job(job)
    payload = job['payload']
    prompt = payload['prompt']
    provider = payload['provider'] || 'openai'
    session_id = job['session_id'] || 'default'
    
    log_operation('ask_handler', 'START', "Provider: #{provider}, Prompt length: #{prompt.length}, Session: #{session_id}")

    # Check for context queries
    if is_context_query?(prompt)
      response = ConversationContext.answer_context_query(session_id, prompt)
      log_operation('ask_handler', 'COMPLETE', "Context query answered for session: #{session_id}")
      
      return {
        'response' => response,
        'provider' => 'context_memory',
        'session_id' => session_id,
        'type' => 'context_query'
      }
    end

    # Store user message in conversation context
    ConversationContext.add_message(session_id, 'user', prompt, {
      'job_id' => job['job_id'],
      'source' => job['source']
    })

    # Call LLM provider via ask.sh
    ask_script = File.join(get_vec3_root, 'dev', 'providers', 'ask.sh')
    
    unless File.exist?(ask_script)
      raise "Provider script not found: #{ask_script}"
    end

    # Build command
    cmd_args = [
      'bash', ask_script,
      '-p', provider
    ]
    
    cmd_args += ['-m', payload['model']] if payload['model']
    cmd_args += ['-s', payload['system_prompt']] if payload['system_prompt']
    cmd_args += ['-t', payload['temperature'].to_s] if payload['temperature']
    cmd_args += ['-x', payload['max_tokens'].to_s] if payload['max_tokens']
    cmd_args << prompt

    # Execute
    require 'open3'
    stdout, stderr, status = Open3.capture3(*cmd_args)

    unless status.success?
      raise "Provider failed: #{stderr}"
    end

    response = stdout.strip

    # Store assistant message in conversation context
    ConversationContext.add_message(session_id, 'assistant', response, {
      'job_id' => job['job_id'],
      'provider' => provider
    })

    log_operation('ask_handler', 'COMPLETE', "Response length: #{response.length}, Session: #{session_id}")

    {
      'response' => response,
      'provider' => provider,
      'model' => payload['model'],
      'prompt_length' => prompt.length,
      'response_length' => response.length,
      'session_id' => session_id
    }
  end

  def is_context_query?(prompt)
    """Check if prompt is asking about conversation context"""
    query = prompt.downcase
    context_patterns = [
      /what (were|are) we (talking|discussing) about/,
      /what (was|is) (our|the) (last |previous )?conversation/,
      /what did (we|i) (say|discuss|talk about)/,
      /remind me what/,
      /conversation (history|context|summary)/
    ]
    
    context_patterns.any? { |pattern| query.match?(pattern) }
  end

  def handle_ingest_job(job)
    payload = job['payload']
    filepath = payload['filepath']
    analysis = job['metadata']['analysis']
    
    log_operation('ingest_handler', 'START', "File: #{File.basename(filepath)}, Action: #{analysis['action']}")

    # Execute analysis actions
    actions_taken = FileAnalyzer.execute_analysis_actions(filepath, analysis)
    
    # Store analysis result
    FileAnalyzer.store_analysis(filepath, analysis, actions_taken)

    log_operation('ingest_handler', 'COMPLETE', "Actions: #{actions_taken.length}")

    {
      'source_path' => filepath,
      'file_type' => payload['file_type'],
      'analysis_action' => analysis['action'],
      'analysis_reason' => analysis['reason'],
      'actions_taken' => actions_taken,
      'processed_at' => Time.now.utc.iso8601
    }
  end

  def handle_telegram_job(job)
    payload = job['payload']
    message = payload['message']
    chat_id = payload['chat_id']
    
    log_operation('telegram_handler', 'START', "Chat: #{chat_id}, Message: #{message[0..50]}")

    # For now, echo back or process as ask job
    # In production, this would integrate with telegram bot reply logic
    
    {
      'chat_id' => chat_id,
      'response' => "Received: #{message}",
      'processed_at' => Time.now.utc.iso8601
    }
  end

  def handle_rest_job(job)
    payload = job['payload']
    endpoint = payload['endpoint']
    method = payload['method']
    
    log_operation('rest_handler', 'START', "Endpoint: #{endpoint}, Method: #{method}")

    # Process REST request
    # Implementation depends on endpoint routing logic
    
    {
      'endpoint' => endpoint,
      'method' => method,
      'processed_at' => Time.now.utc.iso8601
    }
  end

  def handle_shell_job(job)
    payload = job['payload']
    command = payload['command']
    
    log_operation('shell_handler', 'START', "Command: #{command}")

    # Process shell command
    # This would route to appropriate shell handler
    
    {
      'command' => command,
      'processed_at' => Time.now.utc.iso8601
    }
  end

  # ============================================================================
  # UNIFIED WATCH STATE
  # ============================================================================

  def initialize_unified_state
    return unless RedisCache.redis_available?

    initial_state = {
      'version' => '1.0.0',
      'started_at' => Time.now.utc.iso8601,
      'sirius_time' => sirius_time(),
      'components' => {},
      'files' => {},
      'locations' => {},
      'heartbeats' => {},
      'last_scan' => nil,
      'last_update' => Time.now.utc.iso8601,
      'watcher_id' => @worker_id
    }
    
    RedisCache.redis_set(REDIS_STATE_KEY, initial_state)
    log_operation('unified_state', 'COMPLETE', 'Unified watch state initialized')
  end

  def scan_component_heartbeats
    return {} unless RedisCache.redis_available?

    conn = RedisCache.get_redis_connection
    return {} unless conn

    heartbeats = {}
    
    begin
      # Get all heartbeat keys (format: heartbeat:COMPONENT:TIMESTAMP)
      keys = conn.keys('heartbeat:*')
      keys.each do |key|
        parts = key.split(':')
        next unless parts.length >= 2
        
        component = parts[1]
        heartbeat_data = RedisCache.redis_get(key)
        
        if heartbeat_data
          timestamp = heartbeat_data['timestamp'] || heartbeat_data[:timestamp]
          age = calculate_heartbeat_age(timestamp)
          
          heartbeats[component] = {
            'last_seen' => timestamp,
            'status' => heartbeat_data['status'] || heartbeat_data[:status] || 'active',
            'metrics' => heartbeat_data['metrics'] || heartbeat_data[:metrics] || {},
            'age_seconds' => age,
            'alive' => age < HEARTBEAT_TIMEOUT
          }
        end
      end

      # Get worker heartbeats (format: worker:ID:heartbeat)
      worker_keys = conn.keys('worker:*:heartbeat')
      worker_keys.each do |key|
        parts = key.split(':')
        worker_id = parts[1]
        worker_data = RedisCache.redis_get(key)
        
        if worker_data
          timestamp = worker_data['timestamp'] || Time.now.utc.iso8601
          age = calculate_heartbeat_age(timestamp)
          
          heartbeats["worker:#{worker_id}"] = {
            'last_seen' => timestamp,
            'status' => 'active',
            'metrics' => worker_data,
            'age_seconds' => age,
            'alive' => age < HEARTBEAT_TIMEOUT
          }
        end
      end

    rescue => e
      log_operation('heartbeat_scan', 'ERROR', "Failed to scan heartbeats: #{e.message}")
    end

    heartbeats
  end

  def calculate_heartbeat_age(timestamp_str)
    return 999999 unless timestamp_str
    
    begin
      timestamp = Time.parse(timestamp_str)
      (Time.now - timestamp).to_i
    rescue
      999999
    end
  end

  def scan_file_system
    project_root = get_project_root
    vec3_root = get_vec3_root
    
    # Key directories to watch
    watch_patterns = [
      File.join(project_root, '!1N.3OX*'),
      File.join(project_root, '!WORKDESK*'),
      File.join(project_root, '!0UT.3OX*'),
      File.join(vec3_root, 'var', 'queue'),
      File.join(vec3_root, 'var', 'receipts'),
      File.join(vec3_root, 'var', 'state')
    ]
    
    file_map = {}
    
    watch_patterns.each do |pattern|
      Dir.glob(pattern).each do |path|
        next unless File.directory?(path)
        
        scan_directory_recursive(path, file_map, project_root)
      end
    end
    
    file_map
  end

  def scan_directory_recursive(dir, file_map, root_prefix)
    Dir.glob(File.join(dir, '**', '*')).each do |path|
      next unless File.file?(path)
      
      begin
        rel_path = path.start_with?(root_prefix) ? path[root_prefix.length..-1].sub(/^\//, '') : path
        stat = File.stat(path)
        
        file_map[rel_path] = {
          'path' => path,
          'size' => stat.size,
          'mtime' => stat.mtime.utc.iso8601,
          'hash' => calculate_file_hash(path),
          'location' => File.dirname(path)
        }
      rescue => e
        # Skip files we can't access
        next
      end
    end
  end

  def calculate_file_hash(path)
    begin
      content = File.read(path)
      Digest::SHA256.hexdigest(content)[0..15]
    rescue
      '0000000000000000'
    end
  end

  def detect_file_changes(current_files, previous_files)
    changes = {
      'new' => [],
      'modified' => [],
      'moved' => [],
      'deleted' => []
    }
    
    # Find new and modified files
    current_files.each do |path, info|
      prev_info = previous_files[path]
      
      if prev_info.nil?
        changes['new'] << path
      elsif info['hash'] != prev_info['hash'] || info['mtime'] != prev_info['mtime']
        changes['modified'] << path
      elsif info['location'] != prev_info['location']
        changes['moved'] << { 'from' => prev_info['location'], 'to' => info['location'], 'path' => path }
      end
    end
    
    # Find deleted files
    previous_files.each do |path, _|
      changes['deleted'] << path unless current_files[path]
    end
    
    changes
  end

  def update_unified_state(heartbeats, files, file_changes)
    return unless RedisCache.redis_available?

    # Build location index
    location_map = {}
    files.each do |path, info|
      location = info['location']
      location_map[location] ||= []
      location_map[location] << {
        'path' => path,
        'size' => info['size'],
        'mtime' => info['mtime'],
        'hash' => info['hash']
      }
    end

    state = {
      'version' => '1.0.0',
      'updated_at' => Time.now.utc.iso8601,
      'sirius_time' => sirius_time(),
      'watcher_id' => @worker_id,
      'components' => {},
      'files' => files,
      'locations' => location_map,
      'heartbeats' => heartbeats,
      'file_changes' => file_changes,
      'last_scan' => Time.now.utc.iso8601,
      'stats' => {
        'total_files' => files.length,
        'active_components' => heartbeats.values.count { |h| h['alive'] },
        'new_files' => file_changes['new'].length,
        'modified_files' => file_changes['modified'].length,
        'moved_files' => file_changes['moved'].length,
        'deleted_files' => file_changes['deleted'].length
      }
    }
    
    # Build component states from heartbeats
    heartbeats.each do |component, heartbeat|
      state['components'][component] = {
        'status' => heartbeat['status'],
        'last_seen' => heartbeat['last_seen'],
        'age_seconds' => heartbeat['age_seconds'],
        'alive' => heartbeat['alive']
      }
    end
    
    # Store in Redis
    RedisCache.redis_set(REDIS_STATE_KEY, state)
    
    # Also store individual file locations for fast lookup
    files.each do |path, info|
      RedisCache.redis_set("cmd.bridge:files:#{path}", info, 86400) # 24h TTL
    end
    
    state
  end

  # ============================================================================
  # WORKER LIFECYCLE
  # ============================================================================

  def send_heartbeat
    now = Time.now
    return if (now - @last_heartbeat) < HEARTBEAT_INTERVAL

    uptime = now - @start_time
    heartbeat_data = {
      'worker_id' => @worker_id,
      'status' => 'active',
      'uptime_seconds' => uptime.to_i,
      'jobs_processed' => @jobs_processed,
      'jobs_failed' => @jobs_failed,
      'timestamp' => now.utc.iso8601
    }

    if RedisCache.redis_available?
      RedisCache.redis_set("worker:#{@worker_id}:heartbeat", heartbeat_data, 60)
    end

    @last_heartbeat = now
    log_operation('worker_heartbeat', 'COMPLETE', "Processed: #{@jobs_processed}, Failed: #{@jobs_failed}")
  end

  def start
    @running = true
    log_operation('brains_start', 'COMPLETE', "Worker: #{@worker_id}, PID: #{Process.pid}")

    puts "▛▞// Brains.exe started"
    puts "▛▞// Worker ID: #{@worker_id}"
    puts "▛▞// Queue: #{QUEUE_NAME}"
    puts "▛▞// Sirius time: #{sirius_time()}"
    puts "▛▞// Polling every #{POLL_INTERVAL}s..."
    puts "▛▞// Unified Watch State: Active (monitoring heartbeats + files)"

    # Setup signal handlers
    trap('INT') { stop }
    trap('TERM') { stop }

    # Main processing loop
    while @running
      begin
        now = Time.now
        
        # Check for jobs
        job = fetch_job
        
        if job
          process_job(job)
        else
          # No job available, sleep briefly
          sleep POLL_INTERVAL
        end

        # Send heartbeat
        send_heartbeat

        # Scan component heartbeats (always)
        heartbeats = scan_component_heartbeats

        # Scan file system (periodic)
        if (now - @last_file_scan) >= FILE_SCAN_INTERVAL
          current_files = scan_file_system
          file_changes = detect_file_changes(current_files, @file_index)
          @file_index = current_files
          @last_file_scan = now
          
          # Update unified state (periodic)
          if (now - @last_state_update) >= STATE_UPDATE_INTERVAL
            state = update_unified_state(heartbeats, current_files, file_changes)
            @last_state_update = now
            
            # Log summary periodically
            active_components = state['components'].values.count { |c| c['alive'] }
            log_operation('unified_state', 'UPDATE', "#{active_components} components, #{current_files.length} files tracked")
          end
        end

      rescue => e
        log_operation('worker_error', 'ERROR', "Exception: #{e.message}")
        puts "▛▞// ERROR: #{e.message}"
        sleep 5  # Brief pause on error
      end
    end

    cleanup
  end

  def stop
    puts "\n▛▞// Stopping brains.exe..."
    @running = false
  end

  def cleanup
    log_operation('brains_stop', 'COMPLETE', "Processed: #{@jobs_processed}, Failed: #{@jobs_failed}")
    
    # Clean up heartbeat
    if RedisCache.redis_available?
      RedisCache.redis_delete("worker:#{@worker_id}:heartbeat")
      
      # Update unified state to mark watcher as stopped
      state = RedisCache.redis_get(REDIS_STATE_KEY)
      if state && state['watcher_id'] == @worker_id
        state['watcher_id'] = nil
        state['stopped_at'] = Time.now.utc.iso8601
        RedisCache.redis_set(REDIS_STATE_KEY, state)
      end
    end

    puts "▛▞// Brains.exe stopped"
    puts "▛▞// Total jobs processed: #{@jobs_processed}"
    puts "▛▞// Total jobs failed: #{@jobs_failed}"
  end
end

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

if __FILE__ == $0
  unless RedisCache.redis_available?
    puts "▛▞// ERROR: Redis not available. Install redis gem: gem install redis"
    exit 1
  end

  conn = RedisCache.get_redis_connection
  unless conn
    puts "▛▞// ERROR: Could not connect to Redis"
    puts "▛▞// Check Redis is running: redis-cli ping"
    exit 1
  end

  begin
    worker = BrainsWorker.new
    worker.start
  rescue => e
    puts "▛▞// FATAL ERROR: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end
