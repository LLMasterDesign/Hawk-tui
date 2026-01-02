#!/usr/bin/env ruby
#
# JOB_SCHEMA.RB :: Unified Job Structure for CMD.BRIDGE Queue
# Defines the standard format for all jobs flowing through the system
#

require 'json'
require 'time'
require 'securerandom'

module JobSchema
  VERSION = '1.0.0'

  # Job types supported by the system
  JOB_TYPES = [
    'ask',           # LLM query
    'ingest.file',   # File processing from station
    'telegram',      # Telegram message
    'rest.request',  # REST API request
    'shell.cmd',     # Interactive shell command
    'heartbeat',     # System heartbeat
    'task.custom'    # Custom task
  ].freeze

  # Job status lifecycle
  JOB_STATUS = [
    'queued',        # In Redis queue
    'processing',    # Picked up by worker
    'completed',     # Successfully completed
    'failed',        # Failed with error
    'cancelled'      # Cancelled by user/system
  ].freeze

  # ============================================================================
  # JOB BUILDER
  # ============================================================================

  def self.create_job(job_type, params = {})
    unless JOB_TYPES.include?(job_type)
      raise ArgumentError, "Invalid job_type: #{job_type}. Must be one of: #{JOB_TYPES.join(', ')}"
    end

    job_id = SecureRandom.hex(8)
    trace_id = params[:trace_id] || job_id

    {
      # Core identifiers
      'job_id' => job_id,
      'trace_id' => trace_id,
      'job_type' => job_type,
      
      # Timestamps
      'created_at' => Time.now.utc.iso8601,
      'queued_at' => Time.now.utc.iso8601,
      'started_at' => nil,
      'completed_at' => nil,
      
      # Status tracking
      'status' => 'queued',
      'progress' => 0,
      'retry_count' => 0,
      'max_retries' => params[:max_retries] || 3,
      
      # Source information
      'source' => params[:source] || 'unknown',
      'actor' => params[:actor] || 'System',
      'session_id' => params[:session_id],
      
      # Job payload (type-specific)
      'payload' => params[:payload] || {},
      
      # Processing config
      'priority' => params[:priority] || 5,  # 1=highest, 10=lowest
      'timeout_seconds' => params[:timeout_seconds] || 300,
      'worker_id' => nil,
      
      # Results
      'result' => nil,
      'error' => nil,
      'receipt_id' => nil,
      
      # Metadata
      'metadata' => params[:metadata] || {},
      'version' => VERSION
    }
  end

  # ============================================================================
  # JOB TYPE SPECIFIC BUILDERS
  # ============================================================================

  def self.ask_job(prompt, opts = {})
    create_job('ask', {
      source: opts[:source] || 'shell',
      actor: opts[:actor] || 'User',
      session_id: opts[:session_id],
      priority: opts[:priority] || 3,
      payload: {
        'prompt' => prompt,
        'system_prompt' => opts[:system_prompt],
        'provider' => opts[:provider] || 'openai',
        'model' => opts[:model],
        'temperature' => opts[:temperature] || 0.7,
        'max_tokens' => opts[:max_tokens] || 4096
      },
      metadata: opts[:metadata] || {}
    })
  end

  def self.ingest_file_job(filepath, file_info, opts = {})
    create_job('ingest.file', {
      source: 'station',
      actor: 'Station',
      trace_id: opts[:trace_id],
      priority: opts[:priority] || 5,
      payload: {
        'filepath' => filepath,
        'file_type' => file_info[:file_type],
        'file_size' => file_info[:size],
        'file_hash' => file_info[:hash],
        'file_mtime' => file_info[:mtime]
      },
      metadata: opts[:metadata] || {}
    })
  end

  def self.telegram_job(message, chat_id, opts = {})
    create_job('telegram', {
      source: 'telegram',
      actor: opts[:username] || 'TelegramUser',
      session_id: "tg_#{chat_id}",
      priority: opts[:priority] || 4,
      payload: {
        'message' => message,
        'chat_id' => chat_id,
        'message_id' => opts[:message_id],
        'username' => opts[:username]
      },
      metadata: opts[:metadata] || {}
    })
  end

  def self.rest_request_job(endpoint, method, params, opts = {})
    create_job('rest.request', {
      source: 'rest_api',
      actor: opts[:user] || 'APIClient',
      session_id: opts[:session_id],
      priority: opts[:priority] || 4,
      payload: {
        'endpoint' => endpoint,
        'method' => method,
        'params' => params,
        'headers' => opts[:headers] || {}
      },
      metadata: opts[:metadata] || {}
    })
  end

  def self.shell_command_job(command, args, opts = {})
    create_job('shell.cmd', {
      source: 'shell',
      actor: opts[:user] || 'ShellUser',
      session_id: opts[:session_id],
      priority: opts[:priority] || 3,
      payload: {
        'command' => command,
        'args' => args
      },
      metadata: opts[:metadata] || {}
    })
  end

  # ============================================================================
  # JOB VALIDATION
  # ============================================================================

  def self.valid_job?(job)
    return false unless job.is_a?(Hash)
    return false unless job['job_id']
    return false unless job['job_type']
    return false unless JOB_TYPES.include?(job['job_type'])
    return false unless job['status']
    return false unless JOB_STATUS.include?(job['status'])
    return false unless job['payload'].is_a?(Hash)
    true
  end

  # ============================================================================
  # JOB STATE UPDATES
  # ============================================================================

  def self.mark_processing(job, worker_id)
    job['status'] = 'processing'
    job['started_at'] = Time.now.utc.iso8601
    job['worker_id'] = worker_id
    job['progress'] = 10
    job
  end

  def self.mark_completed(job, result, receipt_id = nil)
    job['status'] = 'completed'
    job['completed_at'] = Time.now.utc.iso8601
    job['progress'] = 100
    job['result'] = result
    job['receipt_id'] = receipt_id
    job
  end

  def self.mark_failed(job, error)
    job['status'] = 'failed'
    job['completed_at'] = Time.now.utc.iso8601
    job['error'] = error
    job['retry_count'] += 1
    job
  end

  def self.update_progress(job, progress, message = nil)
    job['progress'] = progress
    job['metadata']['progress_message'] = message if message
    job
  end
end

# Example usage when loaded standalone
if __FILE__ == $0
  require 'pp'

  puts "▛▞// JobSchema v#{JobSchema::VERSION}"
  puts "▛▞// Supported job types: #{JobSchema::JOB_TYPES.join(', ')}"
  puts

  # Example: Create an ask job
  job = JobSchema.ask_job("What is the meaning of life?", {
    source: 'shell',
    provider: 'openai',
    model: 'gpt-4o'
  })

  puts "▛▞// Example Ask Job:"
  pp job
  puts
  puts "▛▞// Valid: #{JobSchema.valid_job?(job)}"
end
