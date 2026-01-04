#!/usr/bin/env ruby
#
# BOT.RB :: Telegram Bot Interface for CMD.BRIDGE
# Minimal skeleton with message routing and receipt logging
#

require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'securerandom'
require 'digest'

# Using HTTP-based Telegram API instead of telegram-bot gem for Ruby 2.7 compatibility
TELEGRAM_AVAILABLE = true

require_relative '../../../dev/ops/lib/helpers.rb'
require_relative '../../../dev/ops/cache/redis.rb'
require_relative '../../../bin/sirius.clock.rb'

class CMDTelegramBot
  include Helpers

  def initialize
    @bot_token = load_bot_token
    @running = false
    @base_url = "https://api.telegram.org/bot#{@bot_token}"
    @offset = 0

    unless @bot_token
      log_operation('telegram_init', 'ERROR', 'TELEGRAM_BOT_TOKEN not found in secrets')
      raise "Telegram bot token not configured"
    end

    log_operation('telegram_init', 'COMPLETE', 'Bot token loaded, using HTTP API')
  end

  def load_bot_token
    # Load from secrets/api.keys
    secrets_file = File.join(get_vec3_root, 'rc', 'secrets', 'api.keys')
    return nil unless File.exist?(secrets_file)

    File.readlines(secrets_file).each do |line|
      line = line.strip
      if line =~ /^TELEGRAM_BOT_TOKEN=(.+)$/
        return $1.strip
      end
    end

    # Also check environment
    ENV['TELEGRAM_BOT_TOKEN']
  end

  def start
    log_operation('telegram_start', 'COMPLETE', 'Starting Telegram bot with HTTP polling')
    @running = true

    Signal.trap('INT') { @running = false }

    while @running
      begin
        process_updates
        sleep 1  # Poll every second
      rescue => e
        log_operation('telegram_error', 'ERROR', "Polling error: #{e.message}")
        sleep 5  # Wait longer on error
      end
    end

    log_operation('telegram_stop', 'COMPLETE', 'Bot stopped')
  rescue => e
    log_operation('telegram_error', 'ERROR', "Bot crashed: #{e.message}")
    raise
  end

  def process_updates
    updates = get_updates
    return unless updates && updates['ok'] && updates['result']

    updates['result'].each do |update|
      begin
        handle_update(update)
        @offset = update['update_id'] + 1
      rescue => e
        log_operation('telegram_error', 'ERROR', "Update handling failed: #{e.message}")
      end
    end
  end

  def get_updates
    uri = URI("#{@base_url}/getUpdates")
    uri.query = URI.encode_www_form({ offset: @offset, limit: 10 })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.code == '200'
      JSON.parse(response.body)
    else
      log_operation('telegram_api', 'ERROR', "getUpdates failed: #{response.code}")
      nil
    end
  rescue => e
    log_operation('telegram_api', 'ERROR', "getUpdates exception: #{e.message}")
    nil
  end

  def send_message(chat_id, text, reply_to_message_id = nil)
    uri = URI("#{@base_url}/sendMessage")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    params = {
      chat_id: chat_id,
      text: text,
      parse_mode: 'Markdown'
    }
    params[:reply_to_message_id] = reply_to_message_id if reply_to_message_id

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(params)

    response = http.request(request)

    if response.code == '200'
      JSON.parse(response.body)
    else
      log_operation('telegram_api', 'ERROR', "sendMessage failed: #{response.code}")
      nil
    end
  rescue => e
    log_operation('telegram_api', 'ERROR', "sendMessage exception: #{e.message}")
    nil
  end

  def handle_update(update)
    message = update['message'] || update['edited_message']
    return unless message && message['text']

    chat_id = message['chat']['id']
    user = message['from']
    user_id = user['id']
    username = user['username'] || "user_#{user_id}"
    text = message['text'].strip
    message_id = message['message_id']

    log_operation('telegram_message', 'INFO', "From: #{username} (#{user_id}), Text: #{text[0..50]}...")

    # Generate message ID for tracking
    msg_id = generate_message_id(message)

    # Create receipt for incoming message
    receipt = create_message_receipt(msg_id, message, 'received')

    # Route the message
    response = route_message(text, username, user_id)

    # Send response back to Telegram
    if response && !response.empty?
      send_message(chat_id, response, message_id)

      # Create receipt for sent message
      create_message_receipt(msg_id + '_response', {
        'chat_id' => chat_id,
        'text' => response,
        'timestamp' => Time.now.utc.iso8601
      }, 'sent')
    end

    log_operation('telegram_response', 'COMPLETE', "Message: #{msg_id}, Response: #{response ? 'sent' : 'none'}")
  end

  def generate_message_id(message)
    timestamp = message['date'] || Time.now.to_i
    "tg_#{message['chat']['id']}_#{message['message_id']}_#{timestamp}"
  end

  def create_message_receipt(message_id, message_data, direction)
    receipt = {
      'timestamp' => Time.now.utc.iso8601,
      'sirius_time' => sirius_time(),
      'actor' => 'telegram_bot',
      'intent' => 'message_' + direction,
      'message_id' => message_id,
      'direction' => direction,
      'platform' => 'telegram',
      'status' => 'processed',
      'trace_id' => Digest::SHA256.hexdigest("#{message_id}|#{Time.now.utc.to_f}")[0..15]
    }

    # Add message-specific data
    if direction == 'received'
      receipt['user_id'] = message_data['from']['id']
      receipt['username'] = message_data['from']['username']
      receipt['chat_id'] = message_data['chat']['id']
      receipt['text'] = message_data['text']
    else
      receipt.merge!(message_data)
    end

    # Store receipt
    if RedisCache.redis_available?
      RedisCache.store_receipt(receipt['trace_id'], receipt, 86400 * 30)
    end

    # Also write to file
    receipts_dir = File.join(get_vec3_root, 'var', 'receipts', 'telegram')
    ensure_dirs(receipts_dir)
    receipt_file = File.join(receipts_dir, "#{receipt['trace_id']}.receipt.json")
    File.write(receipt_file, JSON.pretty_generate(receipt))

    receipt
  end

  def route_message(text, username, user_id)
    # Basic command routing
    case text.downcase
    when '/start'
      return welcome_message(username)
    when '/help'
      return help_message
    when '/status'
      return status_message
    when '/clock'
      return clock_message
    else
      # Default: route to AI assistant
      return ask_ai(text, username, user_id)
    end
  end

  def welcome_message(username)
    sirius = sirius_time()
    "▛▞// Welcome to CMD.BRIDGE, #{username}!\n" +
    "▛▞// Sirius time: #{sirius}\n" +
    "▛▞// Send me a message or use /help for commands"
  end

  def help_message
    "▛▞// CMD.BRIDGE Telegram Commands:\n" +
    "▛▞// /start - Welcome message\n" +
    "▛▞// /help - This help\n" +
    "▛▞// /status - System status\n" +
    "▛▞// /clock - Current Sirius time\n" +
    "▛▞// Any other message is sent to the AI assistant"
  end

  def status_message
    redis_status = RedisCache.redis_available? ? 'available' : 'unavailable'
    queue_depth = RedisCache.redis_available? ? RedisCache.queue_length('jobs') : 0

    "▛▞// System Status:\n" +
    "▛▞// Redis: #{redis_status}\n" +
    "▛▞// Job queue: #{queue_depth} items\n" +
    "▛▞// Version: 3.0.0"
  end

  def clock_message
    sirius = sirius_time()
    local_time = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

    "▛▞// Local time: #{local_time}\n" +
    "▛▞// Sirius time: #{sirius}"
  end

  def ask_ai(prompt, username, user_id)
    # Teleprompter pattern: Create job and push to Redis queue
    job_id = SecureRandom.hex(16)
    trace_id = Digest::SHA256.hexdigest("#{user_id}#{Time.now.to_f}")[0..15]
    
    job = {
      'job_id' => job_id,
      'job_type' => 'cursor_ask',
      'trace_id' => trace_id,
      'base_id' => 'CMD.BRIDGE',
      'station_id' => 'GENERAL',
      'thread_id' => "tg_#{user_id}",
      'chat_id' => user_id.to_s,
      'topic_thread_id' => nil,  # Telegram doesn't use topic threads
      'payload' => {
        'prompt' => prompt,
        'username' => username,
        'user_id' => user_id
      },
      'created_at' => Time.now.utc.iso8601
    }
    
    # Push to Redis queue if available
    if RedisCache.redis_available?
      begin
        redis = RedisCache.get_redis_connection
        redis.lpush('queue:jobs', JSON.generate(job))
        log_operation('telegram_job', 'COMPLETE', "Job #{job_id} queued for user #{username}")
        
        # Wait for result (with timeout)
        result = wait_for_job_result(job_id, timeout: 30)
        
        if result && result['status'] == 'ok'
          response_text = result.dig('reply', 'text') || result.dig('reply', 'text')
          return response_text || "▛▞// Response received but empty"
        elsif result && result['status'] == 'error'
          error_msg = result.dig('reply', 'text') || 'Unknown error'
          return "▛▞// Error: #{error_msg}"
        else
          log_operation('telegram_job', 'WARNING', "Job #{job_id} timed out or failed")
          return "▛▞// Request timed out. Please try again."
        end
      rescue => e
        log_operation('telegram_job', 'ERROR', "Job queue error: #{e.message}")
        # Fallback to direct ask.sh call
        return ask_ai_fallback(prompt, username, user_id)
      end
    else
      # Fallback to direct ask.sh call if Redis unavailable
      log_operation('telegram_ask', 'WARNING', 'Redis unavailable, using fallback')
      return ask_ai_fallback(prompt, username, user_id)
    end
  end

  def wait_for_job_result(job_id, timeout: 30)
    """Wait for job result from Redis"""
    start_time = Time.now
    result_key = "result:#{job_id}"
    
    while (Time.now - start_time) < timeout
      if RedisCache.redis_available?
        begin
          redis = RedisCache.get_redis_connection
          result_json = redis.get(result_key)
          
          if result_json
            result = JSON.parse(result_json)
            # Clean up result key
            redis.del(result_key)
            return result
          end
        rescue => e
          log_operation('telegram_wait', 'ERROR', "Error waiting for result: #{e.message}")
          break
        end
      end
      
      sleep 0.5  # Poll every 500ms
    end
    
    nil
  end

  def ask_ai_fallback(prompt, username, user_id)
    """Fallback: Call ask.sh directly when queue unavailable"""
    ask_script = File.join(get_vec3_root, 'dev', 'providers', 'ask.sh')

    if File.exist?(ask_script)
      begin
        # Execute ask.sh with the prompt using IO.popen
        output = ""
        IO.popen(['bash', ask_script, prompt], 'r') do |io|
          output = io.read
        end
        status = $?

        if status.success? && !output.empty?
          return "▛▞// AI Response:\n#{output.strip}"
        else
          return "▛▞// Sorry, I couldn't get a response from the AI assistant right now."
        end
      rescue => e
        log_operation('telegram_ask', 'ERROR', "Failed for user #{username}: #{e.message}")
        return "▛▞// Error communicating with AI assistant."
      end
    else
      return "▛▞// AI assistant not available."
    end
  end

  # ============================================================================
  # UTILITY METHODS
  # ============================================================================

  def stop
    @running = false
    log_operation('telegram_stop', 'COMPLETE', 'Bot shutdown requested')
  end

  def running?
    @running
  end
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __FILE__ == $0
  begin
    puts "▛▞// Starting CMD.BRIDGE Telegram Bot"
    puts "▛▞// Sirius time: #{sirius_time()}"
    puts "▛▞// Bot will listen for messages..."

    bot = CMDTelegramBot.new
    bot.start

  rescue => e
    puts "▛▞// Fatal error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end