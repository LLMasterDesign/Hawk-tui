#!/usr/bin/env ruby
#
# REDIS.RB :: Redis Integration Module for CMD.BRIDGE
# Ported and adapted from VSO.Agent cache/redis.rb
#

begin
  require 'redis'
  REDIS_AVAILABLE = true
rescue LoadError
  REDIS_AVAILABLE = false
end

require_relative '../lib/helpers.rb'

module RedisCache
  include Helpers
  extend self

  # ============================================================================
  # CONNECTION MANAGEMENT
  # ============================================================================

  @@redis_connection = nil
  @@connection_config = nil

  def redis_available?
    REDIS_AVAILABLE
  end

  def get_redis_config
    return @@connection_config if @@connection_config

    # Load from environment or config file
    config = {
      host: ENV['REDIS_HOST'] || 'localhost',
      port: (ENV['REDIS_PORT'] || '6379').to_i,
      db: (ENV['REDIS_DB'] || '0').to_i,
      password: ENV['REDIS_PASSWORD'],
      timeout: (ENV['REDIS_TIMEOUT'] || '5').to_f
    }

    # Try to load from api.keys file
    secrets_file = File.join(get_vec3_root, 'rc', 'secrets', 'api.keys')
    if File.exist?(secrets_file)
      File.readlines(secrets_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        if line =~ /^REDIS_HOST=(.+)$/
          config[:host] = $1.strip
        elsif line =~ /^REDIS_PORT=(.+)$/
          config[:port] = $1.strip.to_i
        elsif line =~ /^REDIS_DB=(.+)$/
          config[:db] = $1.strip.to_i
        elsif line =~ /^REDIS_PASSWORD=(.+)$/
          password = $1.strip
          config[:password] = password.empty? ? nil : password
        elsif line =~ /^REDIS_TIMEOUT=(.+)$/
          config[:timeout] = $1.strip.to_f
        end
      end
    end

    # Try to load from config file (legacy support)
    config_file = File.join(get_vec3_root, 'rc', 'redis.toml')
    if File.exist?(config_file)
      file_config = load_config_file(config_file)
      config.merge!(file_config['redis'] || {})
    end

    @@connection_config = config
    config
  end

  def get_redis_connection
    return nil unless redis_available?

    return @@redis_connection if @@redis_connection

    config = get_redis_config

    begin
      @@redis_connection = Redis.new(
        host: config[:host],
        port: config[:port],
        db: config[:db],
        password: config[:password],
        timeout: config[:timeout]
      )

      # Test connection
      result = @@redis_connection.ping
      log_operation('redis_connection', 'COMPLETE', "Host: #{config[:host]}:#{config[:port]}, DB: #{config[:db]}, Ping: #{result}")
      @@redis_connection

    rescue => e
      log_operation('redis_connection', 'ERROR', "Failed to connect: #{e.message} (#{e.class})")
      nil
    end
  end

  # ============================================================================
  # BASIC OPERATIONS
  # ============================================================================

  def redis_get(key)
    return nil unless redis_available?

    conn = get_redis_connection
    return nil unless conn

    begin
      value = conn.get(key)
      return nil unless value

      # Try to parse JSON, otherwise return as string
      begin
        JSON.parse(value)
      rescue
        value
      end
    rescue => e
      log_operation('redis_get', 'ERROR', "Key: #{key}, Error: #{e.message}")
      nil
    end
  end

  def redis_set(key, value, ttl_seconds = nil)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      # Serialize value to JSON if it's not a string
      serialized_value = if value.is_a?(String)
        value
      else
        JSON.generate(value)
      end

      if ttl_seconds
        result = conn.setex(key, ttl_seconds, serialized_value)
      else
        result = conn.set(key, serialized_value)
      end

      log_operation('redis_set', 'COMPLETE', "Key: #{key}, TTL: #{ttl_seconds}")
      result == 'OK'

    rescue => e
      log_operation('redis_set', 'ERROR', "Key: #{key}, Error: #{e.message}")
      false
    end
  end

  def redis_delete(key)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      result = conn.del(key)
      log_operation('redis_delete', 'COMPLETE', "Key: #{key}, Deleted: #{result > 0}")
      result > 0
    rescue => e
      log_operation('redis_delete', 'ERROR', "Key: #{key}, Error: #{e.message}")
      false
    end
  end

  def redis_exists?(key)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      conn.exists(key) > 0
    rescue => e
      false
    end
  end

  def redis_expire(key, ttl_seconds)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      result = conn.expire(key, ttl_seconds)
      log_operation('redis_expire', 'COMPLETE', "Key: #{key}, TTL: #{ttl_seconds}")
      result
    rescue => e
      log_operation('redis_expire', 'ERROR', "Key: #{key}, Error: #{e.message}")
      false
    end
  end

  # ============================================================================
  # BATCH OPERATIONS
  # ============================================================================

  def redis_mget(*keys)
    return [] unless redis_available?

    conn = get_redis_connection
    return [] unless conn

    begin
      values = conn.mget(*keys)
      values.map do |value|
        next nil unless value
        begin
          JSON.parse(value)
        rescue
          value
        end
      end
    rescue => e
      log_operation('redis_mget', 'ERROR', "Keys: #{keys.join(', ')}, Error: #{e.message}")
      []
    end
  end

  def redis_mset(key_value_pairs)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      serialized_pairs = key_value_pairs.map do |key, value|
        serialized_value = if value.is_a?(String)
          value
        else
          JSON.generate(value)
        end
        [key, serialized_value]
      end

      result = conn.mset(*serialized_pairs.flatten)
      log_operation('redis_mset', 'COMPLETE', "Keys: #{key_value_pairs.keys.join(', ')}")
      result == 'OK'

    rescue => e
      log_operation('redis_mset', 'ERROR', "Error: #{e.message}")
      false
    end
  end

  # ============================================================================
  # RECEIPT OPERATIONS
  # ============================================================================

  def store_receipt(receipt_id, receipt_data, ttl_seconds = 86400 * 30) # 30 days default
    receipt_key = "receipt:#{receipt_id}"
    redis_set(receipt_key, receipt_data, ttl_seconds)
  end

  def get_receipt(receipt_id)
    receipt_key = "receipt:#{receipt_id}"
    redis_get(receipt_key)
  end

  def list_receipts(pattern = "*", limit = 100)
    return [] unless redis_available?

    conn = get_redis_connection
    return [] unless conn

    begin
      keys = conn.keys("receipt:#{pattern}")
      return [] if keys.empty?

      keys = keys.first(limit) if keys.length > limit
      values = redis_mget(*keys)

      keys.zip(values).map do |key, value|
        {
          receipt_id: key.sub('receipt:', ''),
          data: value
        }
      end.compact

    rescue => e
      log_operation('receipt_list', 'ERROR', "Pattern: #{pattern}, Error: #{e.message}")
      []
    end
  end

  # ============================================================================
  # SESSION OPERATIONS
  # ============================================================================

  def store_session(session_id, session_data, ttl_seconds = 86400) # 24 hours default
    session_key = "session:#{session_id}"
    redis_set(session_key, session_data, ttl_seconds)
  end

  def get_session(session_id)
    session_key = "session:#{session_id}"
    redis_get(session_key)
  end

  def update_session(session_id, updates)
    current = get_session(session_id) || {}
    updated = current.merge(updates)
    store_session(session_id, updated)
  end

  def delete_session(session_id)
    session_key = "session:#{session_id}"
    redis_delete(session_key)
  end

  # ============================================================================
  # QUEUE OPERATIONS
  # ============================================================================

  def queue_push(queue_name, item)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      queue_key = "queue:#{queue_name}"
      serialized_item = item.is_a?(String) ? item : JSON.generate(item)

      result = conn.lpush(queue_key, serialized_item)
      log_operation('queue_push', 'COMPLETE', "Queue: #{queue_name}, Item: #{serialized_item[0..50]}...")
      result > 0

    rescue => e
      log_operation('queue_push', 'ERROR', "Queue: #{queue_name}, Error: #{e.message}")
      false
    end
  end

  def queue_pop(queue_name)
    return nil unless redis_available?

    conn = get_redis_connection
    return nil unless conn

    begin
      queue_key = "queue:#{queue_name}"
      result = conn.rpop(queue_key)

      if result
        begin
          JSON.parse(result)
        rescue
          result
        end
      end

    rescue => e
      log_operation('queue_pop', 'ERROR', "Queue: #{queue_name}, Error: #{e.message}")
      nil
    end
  end

  def queue_length(queue_name)
    return 0 unless redis_available?

    conn = get_redis_connection
    return 0 unless conn

    begin
      queue_key = "queue:#{queue_name}"
      conn.llen(queue_key)
    rescue => e
      0
    end
  end

  def queue_peek(queue_name, count = 1)
    return [] unless redis_available?

    conn = get_redis_connection
    return [] unless conn

    begin
      queue_key = "queue:#{queue_name}"
      results = conn.lrange(queue_key, 0, count - 1)

      results.map do |item|
        begin
          JSON.parse(item)
        rescue
          item
        end
      end

    rescue => e
      []
    end
  end

  # ============================================================================
  # PUB/SUB OPERATIONS
  # ============================================================================

  def publish(channel, message)
    return false unless redis_available?

    conn = get_redis_connection
    return false unless conn

    begin
      serialized_message = message.is_a?(String) ? message : JSON.generate(message)
      result = conn.publish(channel, serialized_message)
      log_operation('redis_publish', 'COMPLETE', "Channel: #{channel}, Subscribers: #{result}")
      true
    rescue => e
      log_operation('redis_publish', 'ERROR', "Channel: #{channel}, Error: #{e.message}")
      false
    end
  end

  # ============================================================================
  # HEALTH & MONITORING
  # ============================================================================

  def redis_health_check
    return { status: 'unavailable', message: 'Redis gem not loaded' } unless redis_available?

    conn = get_redis_connection
    unless conn
      return { status: 'disconnected', message: 'Could not establish connection' }
    end

    begin
      start_time = Time.now
      conn.ping
      response_time = Time.now - start_time

      info = conn.info
      db_size = info['db0'] ? info['db0']['keys'] : 0

      {
        status: 'healthy',
        response_time_ms: (response_time * 1000).round(2),
        db_size: db_size,
        version: info['redis_version'],
        uptime_seconds: info['uptime_in_seconds']
      }
    rescue => e
      {
        status: 'error',
        message: e.message,
        last_error_time: Time.now.utc.iso8601
      }
    end
  end

  def get_stats
    return {} unless redis_available?

    conn = get_redis_connection
    return {} unless conn

    begin
      info = conn.info
      {
        total_keys: info.values.sum { |db| db.is_a?(Hash) ? db['keys'].to_i : 0 },
        uptime_seconds: info['uptime_in_seconds'].to_i,
        memory_used: info['used_memory_human'],
        connected_clients: info['connected_clients'].to_i,
        total_commands_processed: info['total_commands_processed'].to_i
      }
    rescue => e
      {}
    end
  end

  # ============================================================================
  # CLEANUP
  # ============================================================================

  def disconnect
    if @@redis_connection
      begin
        @@redis_connection.quit
      rescue
        # Ignore errors during disconnect
      end
      @@redis_connection = nil
    end
  end

  # Auto-disconnect on exit
  at_exit { disconnect }
end