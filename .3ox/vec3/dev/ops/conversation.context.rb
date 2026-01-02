#!/usr/bin/env ruby
#
# CONVERSATION.CONTEXT.RB :: Redis-backed Conversation Memory for CMD.BRIDGE
# Stores conversation history to enable "what were we talking about?" queries
#

require 'json'
require 'time'
require 'digest'
require_relative '../dev/ops/cache/redis.rb'
require_relative '../dev/ops/lib/helpers.rb'

module ConversationContext
  include Helpers
  extend self

  MAX_CONTEXT_MESSAGES = 50  # Keep last 50 messages
  CONTEXT_TTL = 86400 * 7     # 7 days

  # ============================================================================
  # CONVERSATION STORAGE
  # ============================================================================

  def add_message(session_id, role, content, metadata = {})
    """Add a message to conversation context"""
    return false unless RedisCache.redis_available?

    message = {
      'role' => role,              # 'user' or 'assistant'
      'content' => content,
      'timestamp' => Time.now.utc.iso8601,
      'message_id' => generate_message_id(session_id, content),
      'metadata' => metadata
    }

    # Add to conversation list
    conv_key = "conversation:#{session_id}"
    RedisCache.get_redis_connection.rpush(conv_key, JSON.generate(message))
    
    # Trim to max length
    RedisCache.get_redis_connection.ltrim(conv_key, -MAX_CONTEXT_MESSAGES, -1)
    
    # Set expiry
    RedisCache.redis_expire(conv_key, CONTEXT_TTL)

    log_operation('conversation_context', 'COMPLETE', "Session: #{session_id}, Role: #{role}")
    
    true
  end

  def get_conversation(session_id, limit = nil)
    """Retrieve conversation history"""
    return [] unless RedisCache.redis_available?

    conv_key = "conversation:#{session_id}"
    conn = RedisCache.get_redis_connection
    
    messages = if limit
      conn.lrange(conv_key, -limit, -1)
    else
      conn.lrange(conv_key, 0, -1)
    end

    messages.map { |msg| JSON.parse(msg) }
  rescue => e
    log_operation('conversation_get', 'ERROR', "Session: #{session_id}, Error: #{e.message}")
    []
  end

  def summarize_conversation(session_id)
    """Get a summary of what was discussed"""
    messages = get_conversation(session_id)
    
    return nil if messages.empty?

    {
      'session_id' => session_id,
      'message_count' => messages.length,
      'first_message_at' => messages.first['timestamp'],
      'last_message_at' => messages.last['timestamp'],
      'user_messages' => messages.count { |m| m['role'] == 'user' },
      'assistant_messages' => messages.count { |m| m['role'] == 'assistant' },
      'topics' => extract_topics(messages),
      'recent_context' => messages.last(5).map { |m| 
        { 
          'role' => m['role'], 
          'preview' => truncate(m['content'], 100),
          'timestamp' => m['timestamp']
        } 
      }
    }
  end

  def answer_context_query(session_id, query)
    """Answer 'what were we talking about?' style questions"""
    messages = get_conversation(session_id, 20)
    
    if messages.empty?
      return "No conversation history found for this session."
    end

    summary = summarize_conversation(session_id)
    
    # Build context response
    response = []
    response << "▛▞// Conversation Context"
    response << "▛▞// Session: #{session_id}"
    response << "▛▞// Messages: #{summary['message_count']} (#{summary['user_messages']} from you, #{summary['assistant_messages']} from me)"
    response << "▛▞// Started: #{format_time(summary['first_message_at'])}"
    response << "▛▞// Last activity: #{format_time(summary['last_message_at'])}"
    response << "▛▞//"
    
    if summary['topics'] && !summary['topics'].empty?
      response << "▛▞// Topics discussed:"
      summary['topics'].each { |topic| response << "▛▞//   • #{topic}" }
      response << "▛▞//"
    end
    
    response << "▛▞// Recent messages:"
    summary['recent_context'].each do |msg|
      time = format_time(msg['timestamp'])
      preview = msg['preview']
      role_label = msg['role'] == 'user' ? 'You' : 'Me'
      response << "▛▞//   [#{time}] #{role_label}: #{preview}"
    end
    
    response.join("\n")
  end

  # ============================================================================
  # TOPIC EXTRACTION
  # ============================================================================

  def extract_topics(messages)
    """Extract main topics from conversation"""
    # Simple keyword extraction from user messages
    user_messages = messages.select { |m| m['role'] == 'user' }
    
    # Combine all user content
    combined_text = user_messages.map { |m| m['content'] }.join(' ').downcase
    
    # Extract potential topics (simple heuristic)
    topics = []
    
    # Look for common technical terms
    tech_terms = {
      'dispatch' => 'Dispatch Architecture',
      'redis' => 'Redis Integration', 
      'imprint' => 'Imprint Governance',
      'file' => 'File Processing',
      'worker' => 'Worker Processes',
      'queue' => 'Job Queue System',
      'telegram' => 'Telegram Integration',
      'receipt' => 'Receipt System',
      'analysis' => 'File Analysis'
    }
    
    tech_terms.each do |keyword, topic|
      topics << topic if combined_text.include?(keyword)
    end
    
    topics.uniq.first(5)
  end

  # ============================================================================
  # UTILITIES
  # ============================================================================

  def generate_message_id(session_id, content)
    content_hash = Digest::SHA256.hexdigest("#{session_id}#{Time.now.to_f}#{content}")[0..15]
    "msg_#{content_hash}"
  end

  def truncate(text, length)
    return text if text.length <= length
    text[0...length] + "..."
  end

  def format_time(iso_time)
    Time.parse(iso_time).strftime('%H:%M')
  rescue
    'unknown'
  end

  def clear_conversation(session_id)
    """Clear conversation history"""
    return false unless RedisCache.redis_available?

    conv_key = "conversation:#{session_id}"
    RedisCache.redis_delete(conv_key)
  end

  # ============================================================================
  # SESSION MANAGEMENT
  # ============================================================================

  def list_active_sessions
    """List all active conversation sessions"""
    return [] unless RedisCache.redis_available?

    conn = RedisCache.get_redis_connection
    keys = conn.keys('conversation:*')
    
    keys.map { |key| key.sub('conversation:', '') }
  end

  def get_session_info(session_id)
    """Get info about a session"""
    summary = summarize_conversation(session_id)
    
    return nil unless summary

    {
      'session_id' => session_id,
      'message_count' => summary['message_count'],
      'last_activity' => summary['last_message_at'],
      'active_duration' => calculate_duration(summary['first_message_at'], summary['last_message_at'])
    }
  end

  def calculate_duration(start_time, end_time)
    """Calculate duration between two timestamps"""
    start_t = Time.parse(start_time)
    end_t = Time.parse(end_time)
    
    diff_seconds = (end_t - start_t).to_i
    
    if diff_seconds < 60
      "#{diff_seconds}s"
    elsif diff_seconds < 3600
      "#{diff_seconds / 60}m"
    else
      "#{diff_seconds / 3600}h"
    end
  rescue
    'unknown'
  end
end

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

if __FILE__ == $0
  require 'optparse'
  
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: conversation.context.rb [command] [options]"
    
    opts.on("-s", "--session ID", "Session ID") do |s|
      options[:session] = s
    end
    
    opts.on("-m", "--message TEXT", "Message content") do |m|
      options[:message] = m
    end
    
    opts.on("-r", "--role ROLE", "Message role (user/assistant)") do |r|
      options[:role] = r
    end
    
    opts.on("-l", "--limit NUM", Integer, "Limit number of messages") do |l|
      options[:limit] = l
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  command = ARGV[0] || 'help'
  
  case command
  when 'add'
    unless options[:session] && options[:message] && options[:role]
      puts "ERROR: --session, --message, and --role required"
      exit 1
    end
    
    success = ConversationContext.add_message(
      options[:session],
      options[:role],
      options[:message]
    )
    
    if success
      puts "▛▞// Message added to session: #{options[:session]}"
      exit 0
    else
      puts "▛▞// ERROR: Failed to add message"
      exit 1
    end
    
  when 'get'
    unless options[:session]
      puts "ERROR: --session required"
      exit 1
    end
    
    messages = ConversationContext.get_conversation(options[:session], options[:limit])
    
    if messages.empty?
      puts "No messages found for session: #{options[:session]}"
      exit 1
    end
    
    messages.each do |msg|
      puts "[#{msg['timestamp']}] #{msg['role']}: #{msg['content']}"
    end
    
  when 'summary'
    unless options[:session]
      puts "ERROR: --session required"
      exit 1
    end
    
    summary = ConversationContext.summarize_conversation(options[:session])
    
    if summary
      puts JSON.pretty_generate(summary)
      exit 0
    else
      puts "No conversation found for session: #{options[:session]}"
      exit 1
    end
    
  when 'context'
    unless options[:session]
      puts "ERROR: --session required"
      exit 1
    end
    
    response = ConversationContext.answer_context_query(options[:session], "what were we talking about?")
    puts response
    
  when 'sessions'
    sessions = ConversationContext.list_active_sessions
    
    if sessions.empty?
      puts "No active sessions"
      exit 0
    end
    
    puts "▛▞// Active Conversations:"
    sessions.each do |session_id|
      info = ConversationContext.get_session_info(session_id)
      puts "▛▞//   #{session_id}: #{info['message_count']} messages, last: #{info['last_activity']}"
    end
    
  when 'clear'
    unless options[:session]
      puts "ERROR: --session required"
      exit 1
    end
    
    ConversationContext.clear_conversation(options[:session])
    puts "▛▞// Cleared conversation: #{options[:session]}"
    
  else
    puts "Commands: add, get, summary, context, sessions, clear"
    puts "Run with -h for help"
  end
end
