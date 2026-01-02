#!/usr/bin/env ruby
#
# HELPERS.RB :: CMD.BRIDGE Shared Utilities Module
# Ported and adapted from VSO.Agent vso.helpers.rb
#

require 'json'
require 'time'
require 'fileutils'
require_relative '../../../bin/sirius.clock.rb'

module Helpers
  # ============================================================================
  # LOGGING & EVENTS
  # ============================================================================

  def get_3ox_log_path
    # Ensure 3ox.log is written to .3ox/3ox.log (not vec3/3ox.log)
    # Path: vec3/dev/ops/lib/helpers.rb -> .3ox/3ox.log
    # Go up 4 levels: lib -> ops -> dev -> vec3 -> .3ox
    lib_dir = File.dirname(File.expand_path(__FILE__))
    dot3ox_dir = File.expand_path(File.join(lib_dir, '..', '..', '..', '..'))
    File.join(dot3ox_dir, '3ox.log')
  end

  def log_operation(operation, status, details = "", metadata = {})
    log_file = get_3ox_log_path

    # Initialize log file with header if it doesn't exist or is empty
    unless File.exist?(log_file) && File.size(log_file) > 0
      header = <<~HEADER
        # 3OX LOG :: CMD.BRIDGE
        # Format: 3 lines per entry, 1 blank line between entries
        # Line 1: [timestamp] [agent]
        # Line 2:   Operation: <operation> :: Status: <status>
        # Line 3:   Details: <details>
        # Location: .3ox/3ox.log
        #
        ///START OF LOG///
      HEADER
      File.open(log_file, "w") { |f| f.write(header) }
    end

    timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    local_timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    agent_id = "[CMD.BRIDGE]"
    sirius_time = sirius_time() rescue "⧗--.---"

    # Determine log level from status
    log_level = case status.to_s.upcase
    when 'ERROR', 'FAILED', 'FAILURE', 'FAULT'
      'ERROR'
    when 'WARNING', 'WARN'
      'WARNING'
    when 'COMPLETE', 'SUCCESS', 'OK', 'DONE'
      'INFO'
    else
      'INFO'
    end

    # Build details string - include metadata if present
    details_str = details.to_s
    if metadata.is_a?(Hash) && !metadata.empty?
      metadata_parts = []
      metadata.each do |key, value|
        next if value.nil? || value.to_s.empty?
        metadata_parts << "#{key.to_s.capitalize.gsub('_', ' ')}: #{value}"
      end
      if !metadata_parts.empty?
        if !details_str.empty?
          details_str = metadata_parts.join(", ") + ", " + details_str
        else
          details_str = metadata_parts.join(", ")
        end
      end
    end

    # Add session if available
    if ENV['CMD_SESSION_ID'] && !details_str.empty?
      details_str += ", Session: #{ENV['CMD_SESSION_ID']}"
    elsif ENV['CMD_SESSION_ID']
      details_str = "Session: #{ENV['CMD_SESSION_ID']}"
    end

    # Add Sirius time to details
    details_str = "Sirius: #{sirius_time}" + (details_str.empty? ? "" : ", #{details_str}")

    # Build the 3-line log entry
    log_entry = "[#{local_timestamp}] #{agent_id}\n"
    log_entry += "  Operation: #{operation} :: Status: #{log_level}\n"
    log_entry += "  Details: #{details_str}\n" unless details_str.empty?
    log_entry += "  Details:\n" if details_str.empty?  # Empty details line for consistency
    log_entry += "\n"  # Blank line separator

    # Write to 3ox.log
    File.open(log_file, "a") { |f| f.write(log_entry) }

    # Also write structured JSON to alternative backend if needed
    if ENV['LOG_TO_JSON'] == '1'
      json_log_file = log_file.sub(/\.log$/, '.jsonl')
      json_entry = {
        timestamp: timestamp,
        level: log_level,
        operation: operation,
        status: status,
        details: details,
        metadata: metadata,
        session_id: ENV['CMD_SESSION_ID'],
        agent: 'CMD.BRIDGE',
        sirius_time: sirius_time
      }
      File.open(json_log_file, "a") { |f| f.puts(JSON.generate(json_entry)) }
    end
  end

  def append_event(message)
    events_dir = File.join(File.dirname(__FILE__), '..', '..', 'var', 'events')
    FileUtils.mkdir_p(events_dir) unless File.directory?(events_dir)

    stream_log = File.join(events_dir, 'stream.log')
    timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    sirius_time = sirius_time() rescue "⧗--.---"
    File.open(stream_log, 'a') { |f| f.puts("[#{timestamp}] [#{sirius_time}] #{message}") }
  end

  # ============================================================================
  # FILE SYSTEM
  # ============================================================================

  def ensure_dirs(*paths)
    paths.each { |p| FileUtils.mkdir_p(p) }
  end

  def safe_read_file(filepath)
    return nil unless File.exist?(filepath) && File.file?(filepath)
    File.read(filepath).strip
  rescue
    nil
  end

  def safe_write_file(filepath, content)
    ensure_dirs(File.dirname(filepath))
    File.write(filepath, content)
  rescue => e
    log_operation('file_write', 'ERROR', "Path: #{filepath}, Error: #{e.message}")
    false
  end

  # ============================================================================
  # CONFIGURATION
  # ============================================================================

  def load_config_file(config_path)
    return {} unless File.exist?(config_path)
    content = File.read(config_path)
    if config_path.end_with?('.json')
      JSON.parse(content)
    elsif config_path.end_with?('.toml')
      # Simple TOML-like parser (for basic config)
      parse_simple_toml(content)
    else
      # Assume key=value format
      parse_key_value(content)
    end
  rescue => e
    log_operation('config_load', 'ERROR', "Path: #{config_path}, Error: #{e.message}")
    {}
  end

  def parse_simple_toml(content)
    config = {}
    current_section = nil

    content.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      if line =~ /^\[(.+)\]$/
        current_section = $1
        config[current_section] ||= {}
      elsif line =~ /^([^=]+)=(.*)$/
        key, value = $1.strip, $2.strip
        value = value.gsub(/^["']|["']$/, '') # Remove quotes
        # Convert to appropriate type
        value = case value.downcase
        when 'true' then true
        when 'false' then false
        when /^\d+$/ then value.to_i
        when /^\d+\.\d+$/ then value.to_f
        else value
        end

        if current_section
          config[current_section][key] = value
        else
          config[key] = value
        end
      end
    end
    config
  end

  def parse_key_value(content)
    config = {}
    content.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      if line =~ /^([^=]+)=(.*)$/
        key, value = $1.strip, $2.strip
        value = value.gsub(/^["']|["']$/, '') # Remove quotes
        config[key] = value
      end
    end
    config
  end

  # ============================================================================
  # UTILITIES
  # ============================================================================

  def generate_id(prefix = '', length = 8)
    timestamp = Time.now.to_i.to_s(36)
    random = SecureRandom.hex(4)
    "#{prefix}#{timestamp}#{random}"[0..length-1]
  end

  def calculate_hash(content)
    require 'digest'
    Digest::SHA256.hexdigest(content.to_s)
  rescue
    'hash_error'
  end

  def validate_json(json_string)
    JSON.parse(json_string)
    true
  rescue
    false
  end

  # ============================================================================
  # PATH HELPERS
  # ============================================================================

  def get_project_root
    # From vec3/dev/ops/lib/helpers.rb -> go up to project root
    lib_dir = File.dirname(File.expand_path(__FILE__))
    vec3_dir = File.dirname(File.dirname(File.dirname(lib_dir)))
    dot3ox_dir = File.dirname(vec3_dir)
    File.dirname(dot3ox_dir)
  end

  def get_dot3ox_root
    # From vec3/dev/ops/lib/helpers.rb -> go up to .3ox
    lib_dir = File.dirname(File.expand_path(__FILE__))
    vec3_dir = File.dirname(File.dirname(File.dirname(lib_dir)))
    File.dirname(vec3_dir)
  end

  def get_vec3_root
    # From vec3/dev/ops/lib/helpers.rb -> go up to vec3
    lib_dir = File.dirname(File.expand_path(__FILE__))
    File.dirname(File.dirname(File.dirname(lib_dir)))
  end

  # ============================================================================
  # VALIDATION
  # ============================================================================

  def validate_file_exists(filepath, description = "")
    if File.exist?(filepath)
      log_operation('file_validation', 'COMPLETE', "#{description} Path: #{filepath}")
      true
    else
      log_operation('file_validation', 'ERROR', "#{description} Missing: #{filepath}")
      false
    end
  end

  def validate_directory_exists(dirpath, create_if_missing = false)
    if File.directory?(dirpath)
      true
    elsif create_if_missing
      begin
        FileUtils.mkdir_p(dirpath)
        log_operation('dir_validation', 'COMPLETE', "Created: #{dirpath}")
        true
      rescue => e
        log_operation('dir_validation', 'ERROR', "Failed to create: #{dirpath}, Error: #{e.message}")
        false
      end
    else
      log_operation('dir_validation', 'ERROR', "Missing: #{dirpath}")
      false
    end
  end

  extend self
end