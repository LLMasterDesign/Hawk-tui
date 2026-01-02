#!/usr/bin/env ruby
#
# STATION.SERVE.RB :: File Watcher and Receipt Generator for CMD.BRIDGE
# Ported and adapted from VSO.Agent station.serve.rb
#

require 'json'
require 'fileutils'
require 'digest'
require 'openssl'
require 'time'
require 'securerandom'

begin
  require 'xxhash'
rescue LoadError
  # Fallback if xxhash not available
  module XXhash
    def self.xxh64(content)
      Digest::SHA256.hexdigest(content.to_s)[0..15]
    end
  end
end

require_relative 'lib/helpers.rb'
require_relative 'cache/redis.rb'
require_relative '../../lib/job_schema.rb'
require_relative 'file.analyzer.rb'

module CMDStation
  include Helpers
  extend self

  def validate_file(filepath)
    unless File.exist?(filepath)
      return { valid: false, error: "File not found" }
    end

    begin
      file_hash = XXhash.xxh64(File.read(filepath)).to_s(16).rjust(16, '0')
    rescue
      file_hash = Digest::SHA256.hexdigest(File.read(filepath))[0..15]
    end

    {
      valid: true,
      path: filepath,
      hash: file_hash,
      size: File.size(filepath),
      mtime: File.mtime(filepath).utc.iso8601
    }
  rescue => e
    { valid: false, error: "Validation failed: #{e.message}" }
  end

  def classify_file(path)
    return 'unknown' unless File.exist?(path)

    ext = File.extname(path).downcase.sub(/^\./,'')

    case ext
    when 'pdf' then 'document.pdf'
    when 'md'  then 'document.markdown'
    when 'txt' then 'document.text'
    when 'json' then 'data.json'
    when 'yaml', 'yml' then 'data.yaml'
    when 'png','jpg','jpeg','gif','webp' then 'image'
    when 'csv' then 'data.csv'
    when 'xml' then 'data.xml'
    when 'html','htm' then 'document.html'
    when 'docx' then 'document.docx'
    when 'xlsx' then 'document.xlsx'
    when 'wav','mp3','m4a','flac' then 'audio'
    when 'mp4','mov','mkv','avi' then 'video'
    when 'zip','tar','gz','tgz','rar' then 'archive'
    when 'exe','bin','app' then 'executable'
    when 'log' then 'log'
    else
      # Check magic bytes for better classification
      classify_by_magic_bytes(path)
    end
  end

  def classify_by_magic_bytes(path)
    return 'unknown' unless File.exist?(path)

    begin
      magic_bytes = File.open(path, 'rb') { |f| f.read(64) }

      case magic_bytes
      when /\A%PDF/ then 'document.pdf'             # %PDF
      when /\A\xFF\xD8\xFF/n then 'image.jpeg'      # JPEG (with 'n' modifier for binary)
      when /\A\x89PNG/n then 'image.png'            # PNG
      when /\AGIF/n then 'image.gif'                # GIF
      when /\ARIFF/n then 'video.avi'               # RIFF (AVI)
      when /\A.{4}ftyp/n then 'video.mp4'           # MP4 (fuzzy match)
      when /\APK\x03\x04/n then 'archive.zip'       # ZIP
      when /\A\x1F\x8B/n then 'archive.gz'          # GZIP
      when /\ABZ/n then 'archive.bz2'               # BZIP2
      else 'file.unknown'
      end
    rescue
      'file.unknown'
    end
  end

  def receipt_secret
    # Look for receipt key in secrets directory
    vec3_root = get_vec3_root
    secrets_dir = File.join(vec3_root, 'rc', 'secrets')
    key_file = File.join(secrets_dir, 'receipt.key')

    return File.read(key_file).strip if File.exist?(key_file)
    return ENV['RECEIPT_HMAC_KEY'] if ENV['RECEIPT_HMAC_KEY'] && !ENV['RECEIPT_HMAC_KEY'].empty?

    # Generate a default key if none exists (for development)
    default_key_file = File.join(secrets_dir, 'receipt.key.default')
    if File.exist?(default_key_file)
      File.read(default_key_file).strip
    else
      # Create a default key for development
      default_key = SecureRandom.hex(32)
      ensure_dirs(secrets_dir)
      File.write(default_key_file, default_key)
      log_operation('receipt_key', 'WARNING', 'Using auto-generated development key')
      default_key
    end
  end

  def hmac_sig(payload)
    key = receipt_secret
    return nil unless key
    OpenSSL::HMAC.hexdigest('SHA256', key, payload)
  end

  def write_receipt(record)
    vec3_root = get_vec3_root
    var_dir = File.join(vec3_root, 'var')
    receipts_dir = File.join(var_dir, 'receipts')
    ensure_dirs(receipts_dir)

    # Canonical JSON (stable key order by sorting)
    sorted = record.keys.sort.each_with_object({}) { |k, acc| acc[k] = record[k] }
    payload = JSON.generate(sorted)
    sig = hmac_sig(payload)
    out = sorted.dup
    out['sig'] = sig if sig

    # Write to daily log file
    day = Time.now.utc.strftime('%Y%m%d')
    daily_file = File.join(receipts_dir, "#{day}.receipts.log")
    File.open(daily_file, 'a') do |f|
      f.puts(JSON.generate(out))
    end

    # Store in Redis if available
    if RedisCache.redis_available?
      receipt_id = record['trace_id'] || generate_receipt_id(record)
      RedisCache.store_receipt(receipt_id, out, 86400 * 30) # 30 days
    end

    # Return the receipt for further processing
    out
  end

  def generate_receipt_id(record)
    content = "#{record['timestamp']}#{record['file']}#{record['hash']}"
    Digest::SHA256.hexdigest(content)[0..15]
  end

  def find_or_create_workdesk
    """Find or create WORKDESK directory at project root level"""

    project_root = get_project_root

    # Search for existing workdesk folders with various naming patterns
    search_patterns = [
      File.join(project_root, "!WORKDESK*"),
      File.join(project_root, "WORKDESK*"),
      File.join(project_root, "!workdesk*"),
      File.join(project_root, "workdesk*")
    ]

    workdesk_folders = search_patterns.flat_map { |pattern| Dir.glob(pattern, File::FNM_CASEFOLD) }.uniq

    if workdesk_folders.empty?
      # Create default workdesk
      workdesk_path = File.join(project_root, "!WORKDESK")
      FileUtils.mkdir_p(workdesk_path)
      log_operation('workdesk', 'COMPLETE', "Created: #{workdesk_path}")
      return workdesk_path
    end

    # Use first existing workdesk
    workdesk_folders.first
  end

  def find_or_create_output_folder
    """Find or create output folder for processed files"""

    project_root = get_project_root

    # Search for existing output folders
    search_patterns = [
      File.join(project_root, "!0UT.3OX*"),
      File.join(project_root, "0UT.3OX*"),
      File.join(project_root, "!0ut.3ox*"),
      File.join(project_root, "0ut.3ox*")
    ]

    output_folders = search_patterns.flat_map { |pattern| Dir.glob(pattern, File::FNM_CASEFOLD) }.uniq

    if output_folders.empty?
      # Check workdesk subdirectory
      workdesk = find_or_create_workdesk
      workdesk_output = File.join(workdesk, "!0UT.3OX")

      if File.directory?(workdesk_output)
        return workdesk_output
      else
        # Create in workdesk
        FileUtils.mkdir_p(workdesk_output)
        log_operation('output_folder', 'COMPLETE', "Created in workdesk: #{workdesk_output}")
        return workdesk_output
      end
    end

    # Use first existing output folder
    output_folders.first
  end

  def station_drop_dir
    project_root = get_project_root

    # Search for existing input folders
    search_patterns = [
      File.join(project_root, "!1N.3OX*"),
      File.join(project_root, "1N.3OX*"),
      File.join(project_root, "!1n.3ox*"),
      File.join(project_root, "1n.3ox*")
    ]

    input_folders = search_patterns.flat_map { |pattern| Dir.glob(pattern, File::FNM_CASEFOLD) }.uniq

    if input_folders.empty?
      # Create default input folder
      input_path = File.join(project_root, "!1N.3OX")
      FileUtils.mkdir_p(input_path)
      log_operation('input_folder', 'COMPLETE', "Created: #{input_path}")
      return input_path
    end

    # Use first existing input folder
    input_folders.first
  end

  def load_station_seen
    vec3_root = get_vec3_root
    status_file = File.join(vec3_root, 'var', 'status.ref')

    return {} unless File.exist?(status_file)

    content = File.read(status_file)
    seen_json = content[/station\.seen:\s*(\{.*\})/m, 1]

    begin
      seen_json ? JSON.parse(seen_json) : {}
    rescue
      {}
    end
  end

  def save_station_seen(seen)
    vec3_root = get_vec3_root
    var_dir = File.join(vec3_root, 'var')
    ensure_dirs(var_dir)

    status_file = File.join(var_dir, 'status.ref')
    snapshot = {
      'updated_at' => Time.now.utc.iso8601,
      'station.seen' => seen
    }

    File.write(status_file, JSON.pretty_generate(snapshot))
  end

  def process_drop_file(path)
    log_operation('station_ingest', 'START', "Processing: #{File.basename(path)}")

    info = validate_file(path)
    unless info[:valid]
      log_operation('station_ingest', 'ERROR', "Validation failed for #{path}: #{info[:error]}")
      return
    end

    # Check for accompanying note file
    note_file = path.sub(File.extname(path), '.note.txt')
    context = {}
    
    if File.exist?(note_file)
      context[:note] = File.read(note_file).strip rescue nil
      log_operation('station_note', 'COMPLETE', "Found note file for: #{File.basename(path)}")
    end

    # Run file analysis
    puts "▛▞// Analyzing file: #{File.basename(path)}"
    analysis = FileAnalyzer.analyze_file(path, context)
    
    puts "▛▞// Analysis: #{analysis[:action]} - #{analysis[:reason]}"

    intent = 'ingest.file'
    actor = 'Station'
    trace_id = Digest::SHA256.hexdigest("#{path}|#{Time.now.utc.to_f}|#{info[:hash]}")[0..15]

    # Create job with analysis data
    job = JobSchema.ingest_file_job(path, {
      file_type: classify_file(path),
      size: info[:size],
      hash: info[:hash],
      mtime: info[:mtime]
    }, {
      trace_id: trace_id,
      priority: analysis[:priority] == 'high' ? 2 : 5,
      metadata: {
        'analysis' => analysis,
        'note' => context[:note]
      }
    })

    # Dispatch to queue via Redis
    if RedisCache.redis_available?
      success = RedisCache.queue_push('jobs', job)
      
      if success
        log_operation('station_dispatch', 'COMPLETE', "Job: #{job['job_id']}, Trace: #{trace_id}, Action: #{analysis[:action]}")
        append_event("station.dispatched file=#{File.basename(path)} job_id=#{job['job_id']} trace_id=#{trace_id} action=#{analysis[:action]}")
        
        # Create initial receipt
        rec = {
          'timestamp' => Time.now.utc.iso8601,
          'sirius_time' => sirius_time(),
          'actor' => actor,
          'intent' => intent,
          'inputs_hash' => info[:hash],
          'file' => path,
          'file_type' => job['payload']['file_type'],
          'file_size' => info[:size],
          'file_mtime' => info[:mtime],
          'status' => 'QUEUED',
          'trace_id' => trace_id,
          'job_id' => job['job_id'],
          'processing_stage' => 'dispatched',
          'analysis_action' => analysis[:action],
          'analysis_reason' => analysis[:reason]
        }
        
        write_receipt(rec)
        
        # Delete note file after processing
        File.delete(note_file) if File.exist?(note_file)
      else
        log_operation('station_dispatch', 'ERROR', "Failed to queue job for: #{File.basename(path)}")
      end
    else
      # Fallback: process synchronously if Redis unavailable
      log_operation('station_dispatch', 'WARNING', 'Redis unavailable, processing synchronously')
      route_file_legacy(path, trace_id, info)
    end

    log_operation('station_ingest', 'COMPLETE', "File: #{File.basename(path)}, Hash: #{info[:hash]}, Trace: #{trace_id}")
  end

  def route_file_legacy(filepath, trace_id, info)
    # Legacy synchronous processing when Redis is unavailable
    file_type = classify_file(filepath)
    output_folder = find_or_create_output_folder
    
    rec = {
      'timestamp' => Time.now.utc.iso8601,
      'sirius_time' => sirius_time(),
      'actor' => 'Station',
      'intent' => 'ingest.file',
      'inputs_hash' => info[:hash],
      'file' => filepath,
      'file_type' => file_type,
      'file_size' => info[:size],
      'file_mtime' => info[:mtime],
      'status' => 'RECEIVED',
      'trace_id' => trace_id,
      'processing_stage' => 'ingest'
    }

    receipt = write_receipt(rec)
    append_event("station.received file=#{File.basename(filepath)} hash=#{info[:hash]} type=#{file_type} trace_id=#{trace_id}")
    
    # Basic routing
    case file_type
    when /^document\./
      append_event("route.document dest=#{output_folder} file=#{File.basename(filepath)}")
    when /^data\./
      append_event("route.data file=#{File.basename(filepath)} type=#{file_type}")
    when /^image\./, /^audio\./, /^video\./
      append_event("route.media file=#{File.basename(filepath)} type=#{file_type}")
    else
      append_event("route.default file=#{File.basename(filepath)} type=#{file_type}")
    end
  end

  def route_file(filepath, receipt)
    # DEPRECATED: Routing now happens via brains.exe workers
    # This function kept for backward compatibility only
    log_operation('route_file', 'WARNING', 'Legacy route_file called - jobs should be processed by brains.exe')
  end

  def serve_station
    drop = station_drop_dir
    puts "▛▞// Station watching: #{drop}"
    puts "▛▞// Sirius time: #{sirius_time()}"

    seen = load_station_seen
    interval = (ENV['STATION_INTERVAL'] || '2').to_i
    heartbeat_interval = (ENV['HEARTBEAT_INTERVAL'] || '60').to_i
    last_heartbeat = Time.now.to_i

    log_operation('station_start', 'COMPLETE', "Drop zone: #{drop}, Interval: #{interval}s")

    loop do
      begin
        # Find new files
        Dir.glob(File.join(drop, '**', '*')).each do |p|
          next unless File.file?(p)
          key = "#{p}|#{File.size(p)}|#{File.mtime(p).to_i}"
          next if seen[key]

          process_drop_file(p)
          seen[key] = Time.now.utc.iso8601
        end

        # Save seen state periodically
        save_station_seen(seen)

        # Periodic heartbeat
        now = Time.now.to_i
        if (now - last_heartbeat) >= heartbeat_interval
          # Trigger heartbeat
          heartbeat_path = File.join(get_vec3_root, 'dev', 'ops', 'lib', 'heartbeat.rb')
          if File.exist?(heartbeat_path)
            system('ruby', heartbeat_path, 'CMD.BRIDGE', 'active') rescue nil
            last_heartbeat = now
          end
        end

      rescue => e
        log_operation('station_error', 'ERROR', "Exception: #{e.message}")
        sleep 5  # Brief pause on error
      end

      sleep interval
    end
  end
end

# If run as standalone script, start the watcher
if __FILE__ == $0
  CMDStation.serve_station
end