#!/usr/bin/env ruby
# wrkdsk.mirror.rb :: Workdesk Mirror Bridge
# Mirrors host !WORKDESK to runtime vec3/var/wrkdsk with dedupe ledger

require 'json'
require 'digest'
require 'fileutils'

class WrkdskMirror
  def initialize
    @vec3_root = File.expand_path('../..', __FILE__)
    @host_workdesk = File.expand_path('../../../!WORKDESK', __FILE__)
    @runtime_wrkdsk = File.join(@vec3_root, 'var', 'wrkdsk')
    @ledger_file = File.join(@vec3_root, 'var', 'state', 'wrkdsk.index.json')

    ensure_directories
    load_ledger
  end

  def sync_once
    puts "🔄 Starting wrkdsk mirror sync..."

    host_files = scan_directory(@host_workdesk)
    runtime_files = scan_directory(@runtime_wrkdsk)

    changes = calculate_changes(host_files, runtime_files)

    apply_changes(changes)
    update_ledger(host_files)

    puts "✓ Sync complete: #{changes[:copied]} copied, #{changes[:removed]} removed"
  end

  def watch_and_sync(interval_seconds = 30)
    puts "👀 Starting wrkdsk mirror watcher (#{interval_seconds}s interval)"

    loop do
      sync_once
      sleep interval_seconds
    end
  rescue Interrupt
    puts "\n👋 Wrkdsk mirror watcher stopped"
  end

  private

  def ensure_directories
    [@runtime_wrkdsk].each do |dir|
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end
  end

  def load_ledger
    @ledger = if File.exist?(@ledger_file)
                JSON.parse(File.read(@ledger_file))
              else
                {
                  "wrkdsk_bridge_version" => "1.0.0",
                  "host_path" => @host_workdesk,
                  "runtime_path" => @runtime_wrkdsk,
                  "last_sync" => nil,
                  "sync_mode" => "mirror",
                  "dedupe_ledger" => {
                    "file_hashes" => {},
                    "processed_files" => [],
                    "ignored_patterns" => [
                      "*.log", "*.tmp", ".git/**", "node_modules/**",
                      "*.swp", "*.bak", ".DS_Store", "Thumbs.db"
                    ]
                  },
                  "sync_stats" => {
                    "files_synced" => 0,
                    "bytes_transferred" => 0,
                    "last_sync_duration_ms" => 0,
                    "errors_count" => 0
                  }
                }
              end
  end

  def save_ledger
    @ledger["last_sync"] = Time.now.utc.iso8601
    File.write(@ledger_file, JSON.pretty_generate(@ledger))
  end

  def scan_directory(base_path)
    files = {}
    ignored_patterns = @ledger["dedupe_ledger"]["ignored_patterns"]

    Dir.glob("#{base_path}/**/*", File::FNM_DOTMATCH).each do |path|
      next unless File.file?(path)
      next if ignored_patterns.any? { |pattern| File.fnmatch(pattern, path.sub(base_path + '/', '')) }

      relative_path = path.sub(base_path + '/', '')
      files[relative_path] = {
        "path" => path,
        "size" => File.size(path),
        "mtime" => File.mtime(path).to_i,
        "hash" => Digest::SHA256.file(path).hexdigest
      }
    end

    files
  end

  def calculate_changes(host_files, runtime_files)
    changes = { copied: 0, removed: 0, files_to_copy: [], files_to_remove: [] }

    # Find files to copy (new or changed in host)
    host_files.each do |rel_path, host_info|
      runtime_info = runtime_files[rel_path]

      if runtime_info.nil? ||
         host_info["hash"] != runtime_info["hash"] ||
         host_info["mtime"] > runtime_info["mtime"]

        changes[:files_to_copy] << rel_path
        changes[:copied] += 1
      end
    end

    # Find files to remove (no longer in host)
    runtime_files.each do |rel_path, runtime_info|
      unless host_files[rel_path]
        changes[:files_to_remove] << rel_path
        changes[:removed] += 1
      end
    end

    changes
  end

  def apply_changes(changes)
    # Copy new/changed files
    changes[:files_to_copy].each do |rel_path|
      host_path = File.join(@host_workdesk, rel_path)
      runtime_path = File.join(@runtime_wrkdsk, rel_path)

      FileUtils.mkdir_p(File.dirname(runtime_path))
      FileUtils.cp(host_path, runtime_path)

      @ledger["sync_stats"]["bytes_transferred"] += File.size(host_path)
    end

    # Remove deleted files
    changes[:files_to_remove].each do |rel_path|
      runtime_path = File.join(@runtime_wrkdsk, rel_path)
      FileUtils.rm_f(runtime_path)
    end

    @ledger["sync_stats"]["files_synced"] += changes[:copied]
  end

  def update_ledger(host_files)
    @ledger["dedupe_ledger"]["file_hashes"] = host_files.transform_values { |info| info["hash"] }
    @ledger["dedupe_ledger"]["processed_files"] = host_files.keys
    save_ledger
  end
end

# Command line interface
if __FILE__ == $0
  mirror = WrkdskMirror.new

  case ARGV[0]
  when 'sync'
    mirror.sync_once
  when 'watch'
    interval = (ARGV[1] || 30).to_i
    mirror.watch_and_sync(interval)
  else
    puts "Usage: ruby wrkdsk.mirror.rb {sync|watch [interval_seconds]}"
    puts "  sync  - Run one-time synchronization"
    puts "  watch - Continuously watch and sync (default 30s interval)"
  end
end